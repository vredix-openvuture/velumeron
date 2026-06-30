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
        QMetaObject::invokeMethod(obj, [obj] { obj->update(); }, Qt::QueuedConnection);
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

    mpv_set_option_string(m_mpv, "terminal", "no");
    mpv_set_option_string(m_mpv, "msg-level", "all=no");
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

void MpvVideo::setSource(const QString &s)
{
    if (m_source == s) return;
    m_source = s;
    if (m_mpv && !s.isEmpty()) {
        QByteArray path = s.toUtf8();
        const char *cmd[] = { "loadfile", path.constData(), nullptr };
        mpv_command_async(m_mpv, 0, cmd);
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
