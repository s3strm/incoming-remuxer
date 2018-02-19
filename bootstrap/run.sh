#!/usr/bin/env bash
export PATH="/usr/local/bin:${PATH}"
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

#function find_tv_imdb_id() {
#  # Should use a queue for this because then dead-letters can be handled
#  aws s3 ls "s3://${MOVIES_BUCKET}/incoming/" 2> /dev/null \
#    | grep -m1 -E "tt[0-9]{7}/$" -e "\.mkv$" -e "\.avi$" \
#    | grep -E -o tt[0-9]+
#  return $?
#}

function find_video() {
  dir=$1
  # Should use a queue for this because then dead-letters can be handled
  aws s3 ls "s3://${MOVIES_BUCKET}/incoming/${dir}" 2> /dev/null \
    | grep -m1 -e "\.mp4$" -e "\.mkv$" -e "\.avi$" \
    | grep -E -o "[^\ ]+$"
  return $?
}

function find_subtitle() {
  dir=$1
  aws s3 ls "s3://${MOVIES_BUCKET}/incoming/${dir}" 2> /dev/null \
    | grep -m1 -e "\.srt$" \
    | grep -E -o "[^\ ]+$"
  return $?
}

function download() {
  echo "downloading s3://${MOVIES_BUCKET}/incoming/$1"
  aws s3 cp "s3://${MOVIES_BUCKET}/incoming/$1" "/dev/shm/$1" > /dev/null
}

function upload() {
  local imdb_id
  imdb_id="$(basename "$1" .mp4)"
  echo "uploading s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4"
  aws s3 cp --storage-class STANDARD_IA \
    "/dev/shm/$1" \
    "s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4" \
    > /dev/null
  if [[ -f "/dev/shm/${imdb_id}.srt" ]]; then
    aws s3 cp --storage-class STANDARD_IA \
      "/dev/shm/${imdb_id}.srt" \
      "s3://${MOVIES_BUCKET}/${imdb_id}/subtitle.srt" \
      > /dev/null
  fi
  return $?
}

function remux() {
  $(dirname "$0")/remuxer "/dev/shm/$1"
}

function cleanup() {
  echo "Scaling down because there are no more videos to process"
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "${AUTO_SCALING_GROUP}" \
    --desired-capacity 0
}

trap '{ cleanup; }' EXIT

which ffmpeg || $(dirname "$0")/download_ffmpeg
which ffmpeg || sleep 1200

### MOVIE #####
for i in $(seq 0 250); do
  video="$(find_video)"
  if [[ ! -z ${video} ]]; then
    video_extension=$(echo "${video}" | grep -E -o "\.[^\.]+$")
    imdb_id="$(basename "${video}" "${video_extension}")"
    download "${video}"
    remux "${video}"
    if [[ $? -eq 0 ]]; then
      original_video=${video}
      video="${imdb_id}.mp4"
      upload "${video}" \
        && aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${original_video}"
    else
      echo "failed to remux ${video}" >&2
      aws s3 cp /dev/shm/${video} "s3://${MOVIES_BUCKET}/incoming/dead_letters/${video}"
      aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${video}"
    fi

    find /dev/shm -iname "${imdb_id}.*" -delete
    unset video imdb_id
  fi

  # new subtitle
  subtitle="$(find_subtitle)"
  if [[ ! -z ${subtitle} ]]; then
    imdb_id="$(basename "${subtitle}" ".srt")"

    input_video="/dev/shm/${imdb_id}.mp4"
    input_sub="/dev/shm/${imdb_id}.srt"
    output_file="/dev/shm/${imdb_id}_sub.mp4"

    echo "downloading s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4"
    aws s3 cp "s3://${MOVIES_BUCKET}/${imdb_id}/video.mp4" "${input_video}" > /dev/null
    echo "downloading s3://${MOVIES_BUCKET}/incoming/${subtitle}"
    aws s3 cp "s3://${MOVIES_BUCKET}/incoming/${subtitle}" "${input_sub}" > /dev/null

    ffmpeg -y             \
      -fflags +genpts     \
      -i "${input_video}"  \
      -f srt -i "${input_sub}" \
      -map 0:0 -map 0:1 -map 1:0 \
      -c:v copy -c:a copy -c:s mov_text \
      "${output_file}"

    if [[ $? -eq 0 ]]; then
      mv "${output_file}" "${input_video}"
      upload "${imdb_id}.mp4" \
        && aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${subtitle}"
    else
      echo "failed to remux ${subtitle}" >&2
      aws s3 cp ${input_sub} "s3://${MOVIES_BUCKET}/incoming/dead_letters/${subtitle}"
      aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${subtitle}"
    fi

    find /dev/shm -iname "${imdb_id}*" -delete
    unset subtitle imdb_id input_video input_sub output_file
  fi

  echo "sleeping before another iteration"
  sleep 10
done

exit

#### TV ######
#while true; do
#  tv_imdb_id="$(find_tv_imdb_id)"
#  while true; do
#    video=$(find_video "${tv_imdb_id}/"
#    [[ -z ${video} ]] && continue
#
#    download "${tv_imdb_id}/${video}"
#    remux "${tv_imdb_id}/${video}"
#    if [[ $? -eq 0 ]]; then
#      original_video=${video}
#      video="${imdb_id}.mp4"
#      upload "${video}" \
#        && aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${original_video}"
#    else
#      echo "failed to remux ${video}" >&2
#      aws s3 cp /dev/shm/${video} "s3://${MOVIES_BUCKET}/incoming/dead_letters/${video}"
#      aws s3 rm "s3://${MOVIES_BUCKET}/incoming/${video}"
#    fi
#
#    find /dev/shm -iname "${imdb_id}.*" -delete
#    unset video imdb_id
#  done
#done
