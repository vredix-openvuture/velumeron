#include "MpvVideo.h"

#include <QtGui/QOpenGLContext>
#include <QtOpenGL/QOpenGLFramebufferObject>
#include <QtQuick/QQuickWindow>
#include <clocale>
#include <stdexcept>

// ── GL proc loader for mpv's render API ──────────────────────────────────────
static void *getProcAddress(void *, const char *name)
{
    QOpenGLContext *ctx = QOpenGLContext::currentContext();
    if (!ctx) return nullptr;
    return reinterpret_cast<void *>(ctx->getProcAddress(QByteArray(name)));
}

// ── Renderer: owns the mpv_render_context and paints each frame into the FBO ──
namespace {
class MpvRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvRenderer(MpvVideo *obj) : m_obj(obj) {}
    ~MpvRenderer() override
    {
        if (m_gl) mpv_render_context_free(m_gl);
    }

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        if (!m_gl) {
            mpv_opengl_init_params glInit{ getProcAddress, nullptr };
            mpv_render_param params[] = {
                { MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL) },
                { MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit },
                { MPV_RENDER_PARAM_INVALID, nullptr },
            };
            if (mpv_render_context_create(&m_gl, m_obj->handle(), params) < 0)
                throw std::runtime_error("MpvVideo: failed to create mpv render context");
            // mpv calls this (possibly off-thread) when a new frame is ready → re-render on the GUI thread.
            mpv_render_context_set_update_callback(m_gl, &MpvRenderer::onMpvUpdate, m_obj);
            // We are on the RENDER thread; hand the news to the item's own thread, where a file that
            // was set before this moment is still waiting to be played.
            QMetaObject::invokeMethod(m_obj, "renderContextCreated", Qt::QueuedConnection);
        }
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo mpfbo{ static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0 };
        // QQuickFramebufferObject's FBO is already top-left origin for Qt compositing; mpv must NOT
        // additionally flip or the video comes out upside-down.
        int flipY = 0;
        mpv_render_param params[] = {
            { MPV_RENDER_PARAM_OPENGL_FBO, &mpfbo },
            { MPV_RENDER_PARAM_FLIP_Y, &flipY },
            { MPV_RENDER_PARAM_INVALID, nullptr },
        };
        mpv_render_context_render(m_gl, params);
        if (m_obj->window()) m_obj->window()->update();
    }

private:
    static void onMpvUpdate(void *ctx)
    {
        auto *obj = static_cast<MpvVideo *>(ctx);
        // mpv has something new to show. Queued onto the item's thread, where it is also the one
        // honest answer to "is there a picture yet" — mpv has no first-frame signal of its own.
        QMetaObject::invokeMethod(obj, [obj] { obj->markFrameReady(); obj->update(); },
                                  Qt::QueuedConnection);
    }

    MpvVideo *m_obj = nullptr;
    mpv_render_context *m_gl = nullptr;
};
} // namespace

// ── MpvVideo ─────────────────────────────────────────────────────────────────
MpvVideo::MpvVideo(QQuickItem *parent) : QQuickFramebufferObject(parent)
{
    // libmpv requires a C numeric locale; Qt/the shell may set another. Without this mpv_create fails.
    std::setlocale(LC_NUMERIC, "C");
    m_mpv = mpv_create();
    if (!m_mpv) throw std::runtime_error("MpvVideo: mpv_create failed");

    // Silent by default — a wallpaper must not print to the shell's log on every frame. But silent
    // also means a file that never plays says NOTHING anywhere, which is a black screen with no
    // reason attached. VELUMERON_MPV_DEBUG=1 turns mpv's own log back on for one run.
    const bool dbg = qEnvironmentVariableIsSet("VELUMERON_MPV_DEBUG");
    mpv_set_option_string(m_mpv, "terminal", dbg ? "yes" : "no");
    mpv_set_option_string(m_mpv, "msg-level", dbg ? "all=v" : "all=no");
    mpv_set_option_string(m_mpv, "config", "no");
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    mpv_set_option_string(m_mpv, "hwdec", "auto");
    mpv_set_option_string(m_mpv, "loop-file", "inf");   // live wallpaper loops forever
    mpv_set_option_string(m_mpv, "audio", "no");
    mpv_set_option_string(m_mpv, "mute", "yes");
    mpv_set_option_string(m_mpv, "keepaspect", "yes");
    mpv_set_option_string(m_mpv, "panscan", "1.0");     // zoom to cover (like Image PreserveAspectCrop)

    if (mpv_initialize(m_mpv) < 0) throw std::runtime_error("MpvVideo: mpv_initialize failed");
}

MpvVideo::~MpvVideo()
{
    if (m_mpv) mpv_terminate_destroy(m_mpv);
}

QQuickFramebufferObject::Renderer *MpvVideo::createRenderer() const
{
    return new MpvRenderer(const_cast<MpvVideo *>(this));
}

// ── Why a file is not simply loaded when it is set ───────────────────────────
// `vo=libmpv` has no output device of its own: it draws through the render context, and that
// context can only be created once Qt hands us a GL context — which happens on the RENDER thread,
// at the first frame, well after QML has finished setting properties. Hand mpv a file before that
// and it tries to open the video output there and then, finds none, and gives up on the file for
// good:
//     [vo/libmpv] No render context set.
//     Error opening/initializing the selected video_out (--vo) device.
//     Video: no video
// It never retries. The wallpaper surface then shows a black rectangle with no error anywhere,
// because mpv is silent by default and everything else about it worked.
//
// That is a RACE, and which side wins depends only on when the source arrives: a wallpaper picked
// while the shell runs lands on a surface that has been rendering for ages and plays; the SAME
// wallpaper restored at startup is set during component construction, before the first frame, and
// stays black — "live wallpapers work until you restart with one active".
//
// So the file waits here until there is something to play it into.
void MpvVideo::loadNow()
{
    if (!m_mpv || m_source.isEmpty()) return;
    QByteArray path = m_source.toUtf8();
    const char *cmd[] = { "loadfile", path.constData(), nullptr };
    mpv_command_async(m_mpv, 0, cmd);
}

void MpvVideo::markFrameReady()
{
    if (m_frameReady || m_source.isEmpty()) return;
    m_frameReady = true;
    emit frameReadyChanged();
}

void MpvVideo::renderContextCreated()
{
    m_renderReady = true;
    if (m_pendingLoad) {
        m_pendingLoad = false;
        loadNow();
    }
}

void MpvVideo::setSource(const QString &s)
{
    if (m_source == s) return;
    m_source = s;
    if (m_frameReady) { m_frameReady = false; emit frameReadyChanged(); }
    if (m_mpv) {
        if (s.isEmpty()) {
            // Nothing to show: drop the file rather than leaving it decoded and paused (the picker
            // parks its player this way between live wallpapers).
            m_pendingLoad = false;
            const char *cmd[] = { "stop", nullptr };
            mpv_command_async(m_mpv, 0, cmd);
        } else if (m_renderReady) {
            loadNow();
        } else {
            m_pendingLoad = true;
        }
    }
    emit sourceChanged();
}

void MpvVideo::setPaused(bool v)
{
    if (m_paused == v) return;
    m_paused = v;
    if (m_mpv) {
        int flag = v ? 1 : 0;
        mpv_set_property_async(m_mpv, 0, "pause", MPV_FORMAT_FLAG, &flag);
    }
    emit pausedChanged();
}

void MpvVideo::setLoop(bool v)
{
    if (m_loop == v) return;
    m_loop = v;
    if (m_mpv) mpv_set_option_string(m_mpv, "loop-file", v ? "inf" : "no");
    emit loopChanged();
}

void MpvVideo::setMute(bool v)
{
    if (m_mute == v) return;
    m_mute = v;
    if (m_mpv) {
        int flag = v ? 1 : 0;
        mpv_set_property_async(m_mpv, 0, "mute", MPV_FORMAT_FLAG, &flag);
    }
    emit muteChanged();
}
