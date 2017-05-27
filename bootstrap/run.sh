#!/usr/bin/env bash
AZ=$(curl 169.254.169.254/latest/meta-data/placement/availability-zone/)
export AWS_DEFAULT_REGION=${AZ::-1}
export INSTANCE_ID

MOVIES_BUCKET=$(
  aws cloudformation list-exports \
    --query 'Exports[?Name==`s3strm-movies-bucket`].Value' \
    --output text
)
export MOVIES_BUCKET

AUTO_SCALING_GROUP=$(
  aws cloudformation describe-stacks \
    --stack-name s3strm-incoming-remuxer \
    --query 'Stacks[].Outputs[?OutputKey==`AutoScalingGroup`].OutputValue' \
    --output text
)

function find_video() {
  aws s3 ls "s3://${MOVIES_BUCKET}/incoming/" \
    | grep -m1 \.mp4$ \
    | grep -E -o "[^\ ]+$"
  return $?
}

function download() {
  aws s3 cp "s3://${MOVIES_BUCKET}/incoming/$1" "/tmp/$1"
}

function upload() {
  aws s3 cp "/tmp/${video}" "s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4" \
    && aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${video}"
}

function cleanup() {
  echo "Scaling down because there are no more videos to process"
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "${AUTO_SCALING_GROUP}" \
    --desired-capacity 0
}

trap '{ cleanup; }' EXIT

while true; do
  video="$(find_video)"
  [[ -z ${video} ]] && exit 0

  video_extension=$(echo "${video}" | grep -E -o "\.[^\.]+$")
  imdb_id="$(basename "${video}" "${video_extension}")"
  download "${video}"
  remux "${video}"
  video="${imdb_id}.mp4"
  upload "${video}"
  find /tmp -iname "${imdb_id}.*" -delete

  unset video imdb_id
done
