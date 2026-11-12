# MusicVideoEncoder

**Batch-create 60fps music videos from audio files and cover artwork using FFmpeg.**

MusicVideoEncoder is a Bash script for Linux that turns a folder of music files and matching cover images into MP4 music videos. It supports landscape, portrait, and 4K output, with a choice of software encoding or AMD AMF hardware encoding when the required components are available.

The script is designed around a simple idea: **the picture does not change, so prepare the artwork once and avoid repeatedly resizing it while the video is encoded.**

---

## Features

- **Batch processing:** process supported audio files in the current directory.
- **Still-image workflow:** scale each distinct cover image once per run, cache the prepared image, and reuse it for tracks that share the same artwork.
- **60fps output:** generate constant-frame-rate 60fps video from the prepared still image.
- **Three output resolutions:**
  - 1920 × 1080 — landscape
  - 1080 × 1920 — portrait
  - 3840 × 2160 — 4K
- **Four encoder choices:**
  - H.264 software (`libx264`)
  - HEVC / H.265 software (`libx265`)
  - H.264 AMD AMF (`h264_amf`)
  - HEVC / H.265 AMD AMF (`hevc_amf`)
- **AMF availability checks:** checks whether FFmpeg exposes the AMF encoders and runs a short test encode before offering them in the menu.
- **Optional AMF runtime installation:** on Arch-based systems, offers to install the `amf-amdgpu` package with `yay` if it is not already installed. It asks first; it does not silently install packages.
- **Software fallback:** if a selected AMF encode fails, the script attempts the corresponding software encoder when that software encoder is available.
- **Audio output:** MP3 at 320kbps and 48kHz.
- **Progress display:** shows encoding progress for the current track.
- **Elapsed time:** reports the time taken for each track, including any first-time cover-image preparation.
- **Safer output handling:** encodes to a temporary MP4 in the output directory and moves it into place only after a non-empty output file has been produced.
- **Automatic cleanup:** removes the temporary image cache and any remaining temporary output file when the script exits.

## Encoders and settings

The script offers the following options. AMF options are only offered when the corresponding FFmpeg encoder is present and its test encode succeeds.

| Menu option | FFmpeg encoder | Settings used |
|---|---|---|
| H.264 Software | `libx264` | `ultrafast`, CRF 20, no B-frames |
| HEVC Software | `libx265` | `ultrafast`, CRF 23, no B-frames |
| H.264 AMD AMF | `h264_amf` | `speed`, CQP, I QP 20 / P QP 22, no B-frames |
| HEVC AMD AMF | `hevc_amf` | `speed`, CQP, I QP 23 / P QP 25, no B-frames |

### Which encoder should I choose?

- **H.264** is generally the safest choice when compatibility with video platforms and devices is the priority.
- **HEVC / H.265** can produce smaller files at comparable visual quality, but compatibility varies by platform, browser, device, and upload workflow.
- **AMD AMF** uses AMD hardware encoding when the driver/runtime and FFmpeg build support it. It is a good option to try when encoding speed is important.
- **Software encoding** uses the CPU. It is useful as a fallback and as a comparison against hardware output.

The fastest option and the best-looking option are not necessarily the same. Actual speed and file size depend on the AMD GPU, driver, FFmpeg build, resolution, audio duration, and selected codec settings. Compare the elapsed times and inspect the resulting videos on your own system.

**There is no AV1 option in this version.** The script currently focuses on H.264 and HEVC.

---

## Requirements

### Required

- Linux
- Bash
- FFmpeg with `ffmpeg` and `ffprobe`
- FFmpeg encoders for at least one supported codec:
  - `libx264` and/or `libx265` for software encoding
  - `h264_amf` and/or `hevc_amf` for AMD AMF encoding
- The following command-line utilities used by the script:
  - `awk`
  - `grep`
  - `sha256sum`
  - `mktemp`
  - `pacman` is used for the optional Arch package check

The script checks for `ffmpeg`, `ffprobe`, `awk`, and `sha256sum` at startup. `grep`, `mktemp`, and `pacman` are also used by the script; `yay` is optional and is only used for the AMF package installation offer.

### AMD AMF hardware encoding

To use AMD AMF, you need all of the following:

1. An AMD GPU and driver stack that supports the desired AMF encoder.
2. The AMD AMF runtime components installed and usable by FFmpeg.
3. An FFmpeg build that includes `h264_amf` and/or `hevc_amf`.

On the author's Arch-based CachyOS setup, the AMF runtime package used is:

```bash
yay -S amf-amdgpu
```

MusicVideoEncoder checks whether the `amf-amdgpu` package is installed using `pacman`. If it is missing and `yay` is available, the script asks whether you want to install it. Answer `y` to approve or press Enter / answer `n` to skip.

Installing the runtime package alone does **not** guarantee that your FFmpeg build includes AMF support. The script checks FFmpeg's encoder list and performs a short real encode test for each AMF encoder. An AMF option is only shown as available when its test succeeds.

If AMF is unavailable, the software encoders remain available when included in your FFmpeg build.

> **Distribution note:** The automatic package check and optional installation prompt are designed for Arch-based systems using `pacman` and `yay`. On other distributions, install and configure the appropriate AMD AMF runtime and FFmpeg support manually. The script's package check is not a universal Linux package-manager detector.

---

## Installation

### 1. Install FFmpeg

On Arch Linux / CachyOS:

```bash
sudo pacman -S --needed ffmpeg
```

Check that FFmpeg and ffprobe are available:

```bash
ffmpeg -version
ffprobe -version
```

Check which supported encoders your FFmpeg build provides:

```bash
ffmpeg -hide_banner -encoders | grep -E 'libx264|libx265|h264_amf|hevc_amf'
```

The available encoders depend on how FFmpeg was built.

### 2. Download the script

Download `MusicVideoEncoder2.6.sh` from this repository.

Make it executable:

```bash
chmod +x MusicVideoEncoder2.6.sh
```

### 3. Optional: install AMD AMF

On Arch-based systems with `yay`:

```bash
yay -S amf-amdgpu
```

You can also simply launch the script. If the package is missing and `yay` is installed, the script will ask whether you want it to install the package.

---

## Preparing your music folder

MusicVideoEncoder processes files in the **current working directory**. Put the audio files and their cover images together in one folder.

### Supported audio formats

The script searches for these extensions, case-insensitively:

- `.wav`
- `.mp3`
- `.m4a`
- `.aiff`
- `.aif`
- `.flac`
- `.ogg`
- `.opus`
- `.aac`
- `.wma`

### Supported cover-image formats

- `.png`
- `.jpg`
- `.jpeg`

### Cover-image matching

The script looks for artwork in this order:

1. **Track-specific artwork:** an image with the same base filename as the audio file.
2. **Shared artwork:** if no track-specific image is found, it looks for `cover.png`, `cover.jpg`, or `cover.jpeg`.

Matching is case-insensitive.

For example:

```text
My Music/
├── MusicVideoEncoder2.6.sh
├── 01 - First Track.flac
├── 01 - First Track.jpg
├── 02 - Second Track.flac
├── 02 - Second Track.png
├── 03 - Third Track.flac
├── cover.jpg
└── ...
```

In this example:

- `01 - First Track.flac` uses `01 - First Track.jpg`.
- `02 - Second Track.flac` uses `02 - Second Track.png`.
- `03 - Third Track.flac` uses the shared `cover.jpg`.

If a track has no matching image and there is no shared cover image, that track is skipped.

**Tip:** Use the same base filename for a track's audio and image. For example, `Song Name.flac` and `Song Name.jpg`.

---

## Running MusicVideoEncoder

Open a terminal in the folder containing your audio files and cover images, then run the script.

If the script is in that folder:

```bash
./MusicVideoEncoder2.6.sh
```

If the script is stored elsewhere, provide its path while keeping the terminal's current directory set to the folder containing the music and artwork. For example:

```bash
/path/to/MusicVideoEncoder2.6.sh
```

The script creates an `output` directory in the current working directory if it does not already exist.

### Step 1: Choose a resolution

The script offers:

| Choice | Resolution | Typical use |
|---|---:|---|
| 1 | 1920 × 1080 | Landscape video |
| 2 | 1080 × 1920 | Portrait video, such as TikTok / Instagram |
| 3 | 3840 × 2160 | 4K landscape video |

The default is 1920 × 1080.

The cover image is scaled with aspect ratio preserved, then centered on a black background to fill the selected output dimensions. This avoids stretching artwork.

### Step 2: Choose an encoder

The menu lists the software encoders and any AMF encoders that passed the startup test.

The default selection prefers H.264 AMD AMF when its test succeeds. Otherwise, it prefers H.264 software when available. If neither is available, it selects a usable HEVC option.

Unavailable encoders are shown as unavailable and cannot be selected.

### Step 3: Let the batch run

The script processes audio files in the current directory. Each successful video is saved in the `output` folder using the audio filename with an `.mp4` extension.

---

## Output specifications

| Property | Output |
|---|---|
| Container | MP4 |
| Video frame rate | Constant 60fps |
| Video resolutions | 1920 × 1080, 1080 × 1920, or 3840 × 2160 |
| Video codecs | H.264 / AVC or HEVC / H.265 |
| Audio codec | MP3 |
| Audio bitrate | 320kbps |
| Audio sample rate | 48kHz |
| Artwork fit | Aspect ratio preserved, centered, black padding |
| MP4 optimization | `+faststart` |

The script adds a one-second delay to the audio and pads the audio by one second. The output is then limited using FFmpeg's `-shortest` option.

The video title metadata is set from the audio filename.

### Output folder example

```text
My Music/
├── output/
│   ├── 01 - First Track.mp4
│   ├── 02 - Second Track.mp4
│   └── 03 - Third Track.mp4
├── 01 - First Track.flac
├── 01 - First Track.jpg
├── 02 - Second Track.flac
├── 02 - Second Track.png
├── 03 - Third Track.flac
├── cover.jpg
└── MusicVideoEncoder2.6.sh
```

The script does not delete or modify the original audio files or source cover images.

---

## How the still-image optimization works

A music video with static cover artwork does not need the original high-resolution image to be resized for every output frame.

MusicVideoEncoder handles the artwork separately:

1. It selects the matching cover image.
2. It scales the image to fit the chosen resolution using FFmpeg's Lanczos scaling.
3. It preserves the original aspect ratio and adds centered black padding where necessary.
4. It stores the prepared image in a temporary cache.
5. It feeds that prepared image to the video encode at 1fps.
6. FFmpeg produces a constant 60fps output by duplicating the still frame.

A shared cover image is prepared once per script run and reused for other tracks that use that same image.

The temporary image cache is stored under the system temporary directory and removed when the script exits.

This avoids repeating the expensive image scaling operation for every video frame. The encoder still has to produce the requested 60fps video stream.

---

## AMF detection and fallback behavior

At startup, the script:

1. Checks whether the `amf-amdgpu` package is installed with `pacman`.
2. If it is missing, offers to install it with `yay` when `yay` is available.
3. Checks FFmpeg's encoder list for `h264_amf` and `hevc_amf`.
4. Runs a short 256 × 256, 30fps test encode for each AMF encoder using the script's speed-oriented CQP settings.
5. Marks each AMF encoder available only if its test encode succeeds.

If a selected AMF encode fails while processing an actual track, the script attempts the corresponding software encoder:

- H.264 AMF → H.264 software (`libx264`)
- HEVC AMF → HEVC software (`libx265`)

The software fallback is only possible when the corresponding software encoder is available in FFmpeg.

A successful small startup test does not guarantee that every resolution or every file will encode successfully. For example, a driver or encoder limitation may only appear at 4K. The real encode fallback is intended to handle that situation when a software alternative is available.

---

## Progress and elapsed time

During each encode, the script displays a progress bar based on FFmpeg's reported output time.

After a track finishes, it prints a completion line similar to:

```text
Done: output/01 - First Track.mp4 (amf_h264) | Elapsed: 00:02:34
```

Elapsed time is shown as:

```text
HH:MM:SS
```

The elapsed time includes cover-image preparation when the image has not already been prepared during the current run, as well as the encoding operation.

If AMF fails and the script retries with software encoding, the reported time includes the failed attempt and the fallback attempt.

---

## Troubleshooting

### No audio files found

Make sure:

- The terminal is in the folder containing the audio files.
- The files use one of the supported extensions.
- The extension is not missing or unusual.

### No cover image found / track skipped

Make sure:

- The cover image is in the same folder as the audio file.
- The image uses `.png`, `.jpg`, or `.jpeg`.
- The image has the same base filename as the audio file, or a shared `cover.png`, `cover.jpg`, or `cover.jpeg` exists.

For example:

```text
Track One.flac
Track One.jpg
```

### AMF is unavailable

Check whether FFmpeg lists the AMF encoders:

```bash
ffmpeg -hide_banner -encoders | grep -E 'h264_amf|hevc_amf'
```

Check whether the AMF runtime package is installed on Arch-based systems:

```bash
pacman -Q amf-amdgpu
```

If FFmpeg does not list the AMF encoders, installing the runtime package alone may not be enough. You need an FFmpeg build that includes AMF support.

If the encoders are listed but their startup tests fail, inspect the FFmpeg / AMD driver setup and test the encoder directly.

### AMF test passes but a real encode fails

A short low-resolution test cannot prove that all output sizes will work. Try a lower resolution to determine whether the problem is specific to 4K, and check whether the corresponding software encoder fallback succeeds.

### The video is not compatible with a platform

Try H.264 instead of HEVC. H.264 is generally the more widely compatible upload format. Platform support and processing behavior can change, so check the requirements of the platform you intend to use.

### A Mesa / RADV warning appears

A Mesa warning in the terminal does not automatically mean that video encoding has failed. Check whether the AMF test passed and whether FFmpeg completes the actual encode. If the video is corrupted or the encode fails, keep the full FFmpeg error output for diagnosis.

### An output file already exists

The script writes to a temporary MP4 first. After a successful encode produces a non-empty file, it moves that file to the final output name. A failed encode should not replace an existing completed output with a partial file.

---

## Known limitations

- Linux Bash script; it is not a Windows or macOS application.
- The automatic AMF package check is specific to Arch-based systems using `pacman`; the optional installation uses `yay`.
- AMF availability depends on the AMD GPU, driver/runtime, and FFmpeg build.
- The script currently supports H.264 and HEVC only; it does not offer AV1.
- Only PNG, JPG, and JPEG cover artwork is searched for.
- Only the listed audio extensions are searched for.
- Files are processed from the current working directory, not from a folder path selected in the menu.
- The output is a static-image music video; it does not add visualizers, waveforms, animations, or subtitles.

---

## Contributing / bug reports

Bug reports and suggestions are welcome.

When reporting an encoding problem, please include:

- Linux distribution and version
- AMD GPU model (if using AMF)
- FFmpeg version (`ffmpeg -version`)
- Selected resolution and encoder
- Whether the AMF startup test passed
- The complete FFmpeg error output
- Whether the same track works with a different encoder

Do not include copyrighted audio or artwork unless you have permission to share it. A short, self-created test file is usually enough to reproduce an issue.

---
<img width="1037" height="658" alt="Screenshot_20261112_212117" src="https://github.com/user-attachments/assets/2ca2209a-6728-4c3e-bf29-aecd5437f120" />

<img width="892" height="590" alt="Screenshot_20261112_212054" src="https://github.com/user-attachments/assets/534da274-1a4c-45fa-a611-8c825f2facba" />

---

**MusicVideoEncoder 2.6**  
A straightforward batch music-video encoder built around FFmpeg, static cover artwork, and speed-focused H.264 / HEVC encoding.
