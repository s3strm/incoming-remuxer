SETTINGS_BUCKET := $(shell aws cloudformation list-exports --query 'Exports[?Name==`s3strm-settings-bucket`].Value' --output text)

BOOTSTRAP_MD5 = $(shell find . -type f ! -name Makefile ! -name latest.tar.bz2 -print0 | xargs -0 cat | md5)
BOOTSTRAP_KEY = bootstraps/incoming-remuxer/${BOOTSTRAP_MD5}.tar.bz2
BOOTSTRAP_KEY_EXISTS := $(shell aws s3 ls "s3://${SETTINGS_BUCKET}/${BOOTSTRAP_KEY}" &>/dev/null; echo $$?)

FFMPEG_SRC = https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-64bit-static.tar.xz
FFMPEG_FILE = $(shell basename ${FFMPEG_SRC})
FFMPEG_EXISTS ?= $(shell aws s3 ls s3://${SETTINGS_BUCKET}/tarballs/${FFMPEG_FILE} | wc -l | tr -d [:blank:])

.PHONY: clean upload bootstrap_key latest.tar.bz2 ffmpeg

latest.tar.bz2:
	@rm -f ./latest.tar.bz2
	@tar jcf latest.tar.bz2 *

upload: latest.tar.bz2 ffmpeg
ifneq ($(BOOTSTRAP_KEY_EXISTS),0)
	@aws s3 cp latest.tar.bz2 s3://${SETTINGS_BUCKET}/${BOOTSTRAP_KEY}
else
	$(info s3://${SETTINGS_BUCKET}/${BOOTSTRAP_KEY} already exists)
endif

bootstrap_key:
	@echo ${BOOTSTRAP_KEY}

ffmpeg:
ifeq (${FFMPEG_EXISTS},0)
	wget ${FFMPEG_SRC} -P /tmp
	aws s3 cp /tmp/${FFMPEG_FILE} s3://${SETTINGS_BUCKET}/tarballs/${FFMPEG_FILE}
else
	$(info ffmpeg already exists)
endif
