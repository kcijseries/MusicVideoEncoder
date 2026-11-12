#!/usr/bin/env bash
set -Eeuo pipefail

# Batch Music Video Encoder 2.6
# - Preserves the tested 2.3 software encoding paths.
# - Adds AMD AMF H.264 and HEVC after checking runtime and actual encoder operation.
# - Scales each unique cover image only once, before encoding.
# - Feeds the scaled still at 1 fps and lets FFmpeg duplicate frames to 60 fps.
# - Never installs packages without explicit confirmation.

export MESA_LOG_LEVEL=error
shopt -s nullglob nocaseglob

for cmd in ffmpeg ffprobe awk sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf 'ERROR: Required command not found: %s\n' "$cmd" >&2
    exit 1
  fi
done

OUTDIR="output"
mkdir -p -- "$OUTDIR"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/music-video-encoder.XXXXXX")
TEMP_OUTPUT=""
cleanup() {
  if [[ -n "$TEMP_OUTPUT" ]]; then
    rm -f -- "$TEMP_OUTPUT"
  fi
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# 1. Find source files
# ------------------------------------------------------------------------------
audio_files=( *.wav *.mp3 *.m4a *.aiff *.aif *.flac *.ogg *.opus *.aac *.wma )
image_files=( *.png *.jpg *.jpeg )
total_files=${#audio_files[@]}

if (( total_files == 0 )); then
  echo "No supported audio files found in the current directory."
  exit 0
fi

if (( ${#image_files[@]} == 0 )); then
  echo "No PNG/JPG/JPEG cover images found in the current directory."
  exit 1
fi

# ------------------------------------------------------------------------------
# 2. Check software encoders and optional AMD AMF support
# ------------------------------------------------------------------------------
AVAILABLE_ENCODERS=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)

has_encoder() {
  local encoder="$1"
  grep -qE "[[:space:]]${encoder}([[:space:]]|$)" <<<"$AVAILABLE_ENCODERS"
}

HAS_LIBX264=false
HAS_LIBX265=false
HAS_AMF_H264=false
HAS_AMF_HEVC=false

has_encoder libx264 && HAS_LIBX264=true
has_encoder libx265 && HAS_LIBX265=true

# The AMF runtime package is separate from FFmpeg's compiled-in AMF encoders.
# Offer installation only when missing; never install without user approval.
if ! pacman -Q amf-amdgpu >/dev/null 2>&1; then
  echo "AMD AMF runtime package (amf-amdgpu): not installed."
  if command -v yay >/dev/null 2>&1; then
    read -r -p "Install amf-amdgpu now using yay? [y/N]: " install_amf
    if [[ "$install_amf" =~ ^[Yy]$ ]]; then
      if yay -S --needed amf-amdgpu; then
        echo "AMF package installation completed."
      else
        echo "WARNING: AMF package installation failed; software encoders remain available."
      fi
    else
      echo "Skipping AMF runtime installation."
    fi
  else
    echo "WARNING: yay was not found. Install amf-amdgpu manually if you want AMF."
  fi
else
  echo "AMD AMF runtime package: installed."
fi

# Check that FFmpeg was built with each AMF encoder, then perform a real
# one-second test encode. Merely listing an encoder is not enough.
AVAILABLE_ENCODERS=$(ffmpeg -hide_banner -encoders 2>/dev/null || true)

probe_amf_encoder() {
  local encoder="$1"
  local -a test_args=()

  if ! grep -qE "[[:space:]]${encoder}([[:space:]]|$)" <<<"$AVAILABLE_ENCODERS"; then
    return 1
  fi

  case "$encoder" in
    h264_amf)
      test_args=(-c:v h264_amf -quality speed -rc cqp -qp_i 20 -qp_p 22 -bf 0)
      ;;
    hevc_amf)
      test_args=(-c:v hevc_amf -quality speed -rc cqp -qp_i 23 -qp_p 25 -bf 0)
      ;;
    *)
      return 1
      ;;
  esac

  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'color=c=black:s=256x256:r=30:d=1' \
    -vf format=nv12 \
    -frames:v 30 -an \
    "${test_args[@]}" -f null - >/dev/null 2>&1
}

if probe_amf_encoder h264_amf; then
  HAS_AMF_H264=true
  echo "AMD AMF H.264: available and test encode passed."
else
  echo "AMD AMF H.264: unavailable or test encode failed."
fi

if probe_amf_encoder hevc_amf; then
  HAS_AMF_HEVC=true
  echo "AMD AMF HEVC: available and test encode passed."
else
  echo "AMD AMF HEVC: unavailable or test encode failed."
fi

if [[ "$HAS_LIBX264" != true && "$HAS_LIBX265" != true &&
      "$HAS_AMF_H264" != true && "$HAS_AMF_HEVC" != true ]]; then
  echo "ERROR: No usable H.264 or HEVC encoder was found." >&2
  exit 1
fi

# Prefer AMF H.264 when its real test succeeds; otherwise retain the known-good
# software H.264 default. HEVC remains selectable explicitly.
if [[ "$HAS_AMF_H264" == true ]]; then
  DEFAULT_ENC=3
  DEFAULT_ENC_LABEL="H.264 (AMD AMF)"
elif [[ "$HAS_LIBX264" == true ]]; then
  DEFAULT_ENC=1
  DEFAULT_ENC_LABEL="H.264 (Software)"
elif [[ "$HAS_AMF_HEVC" == true ]]; then
  DEFAULT_ENC=4
  DEFAULT_ENC_LABEL="HEVC (AMD AMF)"
else
  DEFAULT_ENC=2
  DEFAULT_ENC_LABEL="HEVC (Software)"
fi

# ------------------------------------------------------------------------------
# 3. Interactive settings
# ------------------------------------------------------------------------------
echo "============================================================"
echo " Batch Music Video Encoder 2.6 (60fps | 320kbps MP3 @ 48kHz)"
echo "============================================================"
echo "Video encoding   : Software and tested AMD AMF options"
echo "Audio files found: $total_files"
echo "------------------------------------------------------------"

echo "Select Resolution (60fps):"
echo "  1) 1920x1080 (Landscape) [Default]"
echo "  2) 1080x1920 (Portrait - TikTok / Instagram)"
echo "  3) 3840x2160 (4K - YouTube)"
read -r -p "Enter choice [1-3] (default 1): " res_choice
res_choice=${res_choice:-1}

case "$res_choice" in
  1) TARGET_W=1920; TARGET_H=1080; RES_LABEL="1920x1080 (Landscape)" ;;
  2) TARGET_W=1080; TARGET_H=1920; RES_LABEL="1080x1920 (Portrait)" ;;
  3) TARGET_W=3840; TARGET_H=2160; RES_LABEL="3840x2160 (4K)" ;;
  *) echo "Invalid resolution selection." >&2; exit 1 ;;
esac

echo
echo "Select Video Encoder (Recommended: $DEFAULT_ENC_LABEL):"
if [[ "$HAS_LIBX264" == true ]]; then
  echo "  1) H.264 (Software - libx264, ultrafast)"
else
  echo "  1) H.264 (Software) [Unavailable]"
fi
if [[ "$HAS_LIBX265" == true ]]; then
  echo "  2) HEVC / H.265 (Software - libx265, ultrafast)"
else
  echo "  2) HEVC / H.265 (Software) [Unavailable]"
fi
if [[ "$HAS_AMF_H264" == true ]]; then
  echo "  3) H.264 (AMD AMF - hardware, speed)"
else
  echo "  3) H.264 (AMD AMF) [Unavailable]"
fi
if [[ "$HAS_AMF_HEVC" == true ]]; then
  echo "  4) HEVC / H.265 (AMD AMF - hardware, speed)"
else
  echo "  4) HEVC / H.265 (AMD AMF) [Unavailable]"
fi
read -r -p "Enter choice [1-4] (default $DEFAULT_ENC): " enc_choice
enc_choice=${enc_choice:-$DEFAULT_ENC}

case "$enc_choice" in
  1)
    [[ "$HAS_LIBX264" == true ]] || { echo "H.264 software encoder unavailable." >&2; exit 1; }
    ENC_MODE="sw_h264"
    ENC_LABEL="H.264 (Software / libx264 ultrafast)"
    ;;
  2)
    [[ "$HAS_LIBX265" == true ]] || { echo "HEVC software encoder unavailable." >&2; exit 1; }
    ENC_MODE="sw_hevc"
    ENC_LABEL="HEVC (Software / libx265 ultrafast)"
    ;;
  3)
    [[ "$HAS_AMF_H264" == true ]] || { echo "H.264 AMF encoder unavailable or failed its test." >&2; exit 1; }
    ENC_MODE="amf_h264"
    ENC_LABEL="H.264 (AMD AMF / speed)"
    ;;
  4)
    [[ "$HAS_AMF_HEVC" == true ]] || { echo "HEVC AMF encoder unavailable or failed its test." >&2; exit 1; }
    ENC_MODE="amf_hevc"
    ENC_LABEL="HEVC (AMD AMF / speed)"
    ;;
  *) echo "Invalid encoder selection." >&2; exit 1 ;;
esac

echo
echo "Starting batch encode: $RES_LABEL @ 60fps | $ENC_LABEL | 320kbps MP3 @ 48kHz"
echo "Speed tuning: ultrafast (software) / speed (AMF), no B-frames. Cover images are scaled once; FFmpeg repeats them to 60fps."
echo "------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 4. Cover-image matching and progress display
# ------------------------------------------------------------------------------
SHARED_COVER=""
for f in "${image_files[@]}"; do
  lower=${f,,}
  if [[ "$lower" == "cover.png" || "$lower" == "cover.jpg" || "$lower" == "cover.jpeg" ]]; then
    SHARED_COVER="$f"
    break
  fi
done

draw_progress_bar() {
  local pct="$1"
  awk -v pct="$pct" -v w=30 'BEGIN {
    if (pct < 0) pct = 0
    if (pct > 100) pct = 100
    filled = int((pct / 100.0) * w + 0.5)
    bar = ""
    for (i = 0; i < w; i++) bar = bar (i < filled ? "█" : "░")
    printf "\r  Encoding: [%s] %5.1f%%   ", bar, pct
  }'
}

format_elapsed() {
  local total_seconds="$1"
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))
  printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds"
}

# Cache scaled cover images by a hash of the original filename. This means a
# shared cover used by many tracks is resized only once during the whole run.
SCALE_FILTER="scale=${TARGET_W}:${TARGET_H}:force_original_aspect_ratio=decrease:flags=lanczos,pad=${TARGET_W}:${TARGET_H}:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1"

get_scaled_image() {
  local source_image="$1"
  local cache_key scaled_image

  read -r cache_key _ < <(printf '%s' "$source_image" | sha256sum)
  scaled_image="$TEMP_DIR/${cache_key}.png"

  if [[ ! -s "$scaled_image" ]]; then
    echo "  Preparing cover image: $source_image" >&2
    if ! ffmpeg -hide_banner -loglevel error -y \
        -i "$source_image" -vf "$SCALE_FILTER" -frames:v 1 "$scaled_image"; then
      rm -f -- "$scaled_image"
      return 1
    fi
  fi

  printf '%s\n' "$scaled_image"
}

# ------------------------------------------------------------------------------
# 5. Encode one track. The still-image input is only 1fps; -r/-fps_mode create
#    a constant 60fps output by duplicating frames after the image is prepared.
# ------------------------------------------------------------------------------
run_encode() {
  local mode="$1"
  local scaled_image="$2"
  local audio="$3"
  local output_file="$4"
  local vf_filter="format=yuv420p"
  local -a video_codec_args=()

  case "$mode" in
    sw_h264)
      # Fastest x264 preset. Retains the known-good 2.3 quality setting.
      video_codec_args=(-c:v libx264 -preset ultrafast -crf 20 -bf 0 -g 600 -pix_fmt yuv420p)
      ;;
    sw_hevc)
      # Fastest x265 preset.
      video_codec_args=(-c:v libx265 -preset ultrafast -crf 23 -bf 0 -x265-params log-level=error -tag:v hvc1 -g 600 -pix_fmt yuv420p)
      ;;
    amf_h264)
      # AMF speed mode with constant-QP rate control; NV12 is AMF's common 8-bit input.
      vf_filter="format=nv12"
      video_codec_args=(-c:v h264_amf -quality speed -rc cqp -qp_i 20 -qp_p 22 -bf 0 -g 600 -pix_fmt nv12)
      ;;
    amf_hevc)
      vf_filter="format=nv12"
      video_codec_args=(-c:v hevc_amf -quality speed -rc cqp -qp_i 23 -qp_p 25 -bf 0 -g 600 -tag:v hvc1 -pix_fmt nv12)
      ;;
    *)
      echo "Internal error: unknown encoder mode '$mode'." >&2
      return 2
      ;;
  esac

  ffmpeg -hide_banner -y \
    -loop 1 -framerate 1 -i "$scaled_image" -i "$audio" \
    -filter_complex '[1:a]adelay=1000:all=1,apad=pad_dur=1[a]' \
    -map 0:v:0 -map '[a]' \
    -vf "$vf_filter" \
    -r 60 -fps_mode cfr \
    "${video_codec_args[@]}" \
    -c:a libmp3lame -b:a 320k -ar 48000 \
    -metadata "title=${audio%.*}" \
    -shortest -movflags +faststart \
    -progress pipe:1 -nostats -loglevel error \
    "$output_file" \
  | while IFS='=' read -r key value; do
      if [[ "$key" == "out_time_us" ]]; then
        pct=$(awk -v cur="$value" -v tot="$CURRENT_DURATION_US" 'BEGIN {
          if (tot > 0) printf "%.1f", (cur / tot) * 100
          else print "0.0"
        }')
        draw_progress_bar "$pct"
      elif [[ "$key" == "progress" && "$value" == "end" ]]; then
        draw_progress_bar 100
      fi
    done
}

# ------------------------------------------------------------------------------
# 6. Process the batch
# ------------------------------------------------------------------------------
current=0
success_count=0
skip_count=0
failure_count=0

for audio in "${audio_files[@]}"; do
  current=$((current + 1))
  name="${audio%.*}"
  img=""

  # Find a track-specific image first (same basename), case-insensitively.
  for f in "${image_files[@]}"; do
    image_base="${f%.*}"
    if [[ "${image_base,,}" == "${name,,}" ]]; then
      img="$f"
      break
    fi
  done

  # Otherwise use cover.png / cover.jpg / cover.jpeg.
  if [[ -z "$img" && -n "$SHARED_COVER" ]]; then
    img="$SHARED_COVER"
  fi

  if [[ -z "$img" ]]; then
    echo "[$current/$total_files] SKIP: No matching cover image for '$audio'."
    skip_count=$((skip_count + 1))
    continue
  fi

  duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio" 2>/dev/null || true)
  if [[ ! "$duration" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "[$current/$total_files] SKIP: Cannot determine duration for '$audio'."
    skip_count=$((skip_count + 1))
    continue
  fi

  # Include the 1-second audio delay and 1-second audio pad in progress total.
  padded_duration=$(awk -v d="$duration" 'BEGIN { printf "%.6f", d + 2.0 }')
  CURRENT_DURATION_US=$(awk -v d="$padded_duration" 'BEGIN { printf "%.0f", d * 1000000 }')

  echo "[$current/$total_files] Processing: $audio (cover: $img)"
  file_start=$SECONDS
  if ! scaled_img=$(get_scaled_image "$img"); then
    file_elapsed=$((SECONDS - file_start))
    printf "  ERROR: Could not prepare cover image '%s'; skipping this track. Elapsed: %s\\n" \
      "$img" "$(format_elapsed "$file_elapsed")"
    failure_count=$((failure_count + 1))
    continue
  fi

  output_file="$OUTDIR/$name.mp4"
  TEMP_OUTPUT="$OUTDIR/.${name}.part.$$.mp4"
  rm -f -- "$TEMP_OUTPUT"

  # Encode using the selected software codec. Keep the final output untouched
  # until FFmpeg has completed successfully and produced a non-empty temporary file.
  encoded=false
  actual_mode="$ENC_MODE"

  if ! run_encode "$actual_mode" "$scaled_img" "$audio" "$TEMP_OUTPUT"; then
    # If AMF fails on a real track (for example, due to a resolution-specific
    # driver limitation), retry with the matching software codec when available.
    rm -f -- "$TEMP_OUTPUT"
    fallback_mode=""
    if [[ "$actual_mode" == "amf_h264" && "$HAS_LIBX264" == true ]]; then
      fallback_mode="sw_h264"
    elif [[ "$actual_mode" == "amf_hevc" && "$HAS_LIBX265" == true ]]; then
      fallback_mode="sw_hevc"
    fi

    if [[ -n "$fallback_mode" ]]; then
      echo ""
      echo "  WARNING: $ENC_LABEL failed. Retrying with ${fallback_mode}."
      actual_mode="$fallback_mode"
      run_encode "$actual_mode" "$scaled_img" "$audio" "$TEMP_OUTPUT" || true
    fi
  fi

  file_elapsed=$((SECONDS - file_start))
  elapsed_label=$(format_elapsed "$file_elapsed")

  if [[ -s "$TEMP_OUTPUT" ]] && mv -f -- "$TEMP_OUTPUT" "$output_file"; then
    echo ""
    echo "  Done: $output_file ($actual_mode) | Elapsed: $elapsed_label"
    encoded=true
    success_count=$((success_count + 1))
  fi

  if [[ "$encoded" != true ]]; then
    rm -f -- "$TEMP_OUTPUT"
    echo "  ERROR: Encoding failed for '$audio' using $ENC_LABEL | Elapsed: $elapsed_label"
    failure_count=$((failure_count + 1))
  fi

  TEMP_OUTPUT=""
done

echo "------------------------------------------------------------"
echo "Batch complete. Successful: $success_count | Skipped: $skip_count | Failed: $failure_count"
echo "Output directory: $OUTDIR"
