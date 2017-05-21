STACK_NAME = s3strm-incoming-remuxer
STACK_TEMPLATE = file://./cfn.yml
ACTION := $(shell ./bin/cloudformation_action $(STACK_NAME))
UPLOAD ?= true

BOOTSTRAP_KEY = $(shell make -C bootstrap bootstrap_key)

export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION
export AWS_ACCESS_KEY_ID

.PHONY = deploy upload

deploy: upload
	@aws cloudformation ${ACTION}-stack                                     \
	  --stack-name "${STACK_NAME}"                                          \
	  --template-body "${STACK_TEMPLATE}"                                   \
	  --parameters                                                          \
	    ParameterKey=BootstrapKey,ParameterValue=${BOOTSTRAP_KEY} 			\
	  --capabilities CAPABILITY_IAM                                         \
	  2>&1
	@aws cloudformation wait stack-${ACTION}-complete \
	  --stack-name ${STACK_NAME}

upload:
ifeq ($(UPLOAD),true)
	@make -C bootstrap upload
endif
