#pragma once

// libmpv → Qt Quick bridge: a QQuickFramebufferObject that plays video into the QML scene graph via
// mpv's OpenGL render API. Used by the Velumeron wallpaper engine for live (video) wallpapers. Static
// images use the built-in Image element — only video needs this. Exposed to QML as `MpvVideo`.
#include <QtQuick/QQuickFramebufferObject>
#include <QString>
#include <mpv/client.h>
#include <mpv/render_gl.h>

class MpvVideo : public QQuickFramebufferObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(MpvVideo)
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY pausedChanged)
    Q_PROPERTY(bool loop   READ loop   WRITE setLoop   NOTIFY loopChanged)
    Q_PROPERTY(bool mute   READ mute   WRITE setMute   NOTIFY muteChanged)
    // False from the moment a new source is set until mpv has actually produced a picture for it.
    // Without it a caller can only guess with a timer — and a guess is either a black flash (too
    // early) or a wait that is over long before anything was wrong with it (too late).
    Q_PROPERTY(bool frameReady READ frameReady NOTIFY frameReadyChanged)

public:
    explicit MpvVideo(QQuickItem *parent = nullptr);
    ~MpvVideo() override;

    Renderer *createRenderer() const override;
    mpv_handle *handle() const { return m_mpv; }

    // Called (queued, from the render thread) the moment the mpv render context exists. Until then
    // mpv has no video output to open, so a file handed over earlier must WAIT here — see the note
    // on the pending load in MpvVideo.cpp.
    Q_INVOKABLE void renderContextCreated();
    // Called from mpv's update callback (queued onto this object's thread): mpv has a picture.
    void markFrameReady();

    QString source() const { return m_source; }
    void setSource(const QString &s);
    bool paused() const { return m_paused; }
    void setPaused(bool v);
    bool loop() const { return m_loop; }
    void setLoop(bool v);
    bool mute() const { return m_mute; }
    void setMute(bool v);
    bool frameReady() const { return m_frameReady; }

signals:
    void sourceChanged();
    void pausedChanged();
    void loopChanged();
    void muteChanged();
    void frameReadyChanged();

private:
    void loadNow();

    mpv_handle *m_mpv = nullptr;
    QString m_source;
    bool m_paused = false;
    bool m_loop = true;
    bool m_mute = true;
    bool m_renderReady = false;   // the render context exists → mpv can open a video output
    bool m_pendingLoad = false;   // a source arrived before it did and still has to be played
    bool m_frameReady  = false;   // mpv has produced a picture for the current source
};
