SETTINGS_BUCKET := $(shell aws cloudformation list-exports --query 'Exports[?Name==`s3strm-settings-bucket`].Value' --output text)

BOOTSTRAP_MD5 = $(shell find . -type f ! -name Makefile ! -name latest.tar.bz2 -print0 | xargs -0 cat | md5)
BOOTSTRAP_KEY = bootstraps/incoming-remuxer/${BOOTSTRAP_MD5}.tar.bz2
BOOTSTRAP_KEY_EXISTS := $(shell aws s3 ls "s3://${SETTINGS_BUCKET}/${BOOTSTRAP_KEY}" &>/dev/null; echo $$?)

.PHONY: clean upload bootstrap_key latest.tar.bz2

latest.tar.bz2:
	@rm -f ./latest.tar.bz2
	@tar jcf latest.tar.bz2 *

upload: latest.tar.bz2
ifneq ($(BOOTSTRAP_KEY_EXISTS),0)
	@aws s3 cp latest.tar.bz2 s3://${SETTINGS_BUCKET}/${BOOTSTRAP_KEY}
else
	$(info s3://${SETTINGS_BUCKET}/${BOOTSTRAP_KEY} already exists)
endif

bootstrap_key:
	@echo ${BOOTSTRAP_KEY}
