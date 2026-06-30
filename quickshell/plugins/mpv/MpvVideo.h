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

public:
    explicit MpvVideo(QQuickItem *parent = nullptr);
    ~MpvVideo() override;

    Renderer *createRenderer() const override;
    mpv_handle *handle() const { return m_mpv; }

    QString source() const { return m_source; }
    void setSource(const QString &s);
    bool paused() const { return m_paused; }
    void setPaused(bool v);
    bool loop() const { return m_loop; }
    void setLoop(bool v);
    bool mute() const { return m_mute; }
    void setMute(bool v);

signals:
    void sourceChanged();
    void pausedChanged();
    void loopChanged();
    void muteChanged();

private:
    mpv_handle *m_mpv = nullptr;
    QString m_source;
    bool m_paused = false;
    bool m_loop = true;
    bool m_mute = true;
};
