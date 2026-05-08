-- GPU selection — dGPU over iGPU
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")
