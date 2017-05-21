#!/usr/bin/env bash
AZ=$(curl 169.254.169.254/latest/meta-data/placement/availability-zone/)
export AWS_DEFAULT_REGION=${AZ::-1}
export INSTANCE_ID

export MOVIES_BUCKET=$(
  aws cloudformation list-exports \
    --query 'Exports[?Name==`s3strm-movies-bucket`].Value' \
    --output text
)

AUTO_SCALING_GROUP=$(
  aws cloudformation describe-stacks \
    --stack-name s3strm-incoming-remuxer \
    --query 'Stacks[].Outputs[?OutputKey==`AutoScalingGroup`].OutputValue' \
    --output text
)

function get_mp4() {
  aws s3 ls s3://${MOVIES_BUCKET}/incoming/ \
    | grep -m1 \.mp4$ \
    | grep -E -o [^\ ]+$
  return $?
}

while true; do
  video="$(get_mp4)"
  if [[ ! -z ${video} ]]; then
    imdb_id="$(basename ${video} .mp4)"
    aws s3 cp s3://${MOVIES_BUCKET}/incoming/${video} /tmp/${video}
    aws s3 cp /tmp/${video} s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4 \
      && aws s3 rm s3://${MOVIES_BUCKET}/incoming/${video} \
      && rm /tmp/${video}
  else
    echo "Scaling down because there are no more videos to process"
    aws autoscaling update-auto-scaling-group \
      --auto-scaling-group-name ${AUTO_SCALING_GROUP} \
      --desired-capacity 0
    exit 0
  fi
  unset video imdb_id
done
