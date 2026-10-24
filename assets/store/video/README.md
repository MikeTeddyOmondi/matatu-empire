# Store video

The gameplay video uploaded in the Creator Dashboard on the start place (Places > Videos).
Roblox rules: real gameplay only, no voice-over or music with lyrics, 3 uploads a month, and
every upload is reviewed.

Capture it in Studio (press K for the fly-through, then record real driving, touting and the
garage; see the README). Save the final cut here as `gameplay.mp4`.

Videos are large: if the file is over about 50 MB, compress it first, for example
`ffmpeg -i raw.mov -vf scale=1920:-2 -c:v libx264 -crf 23 -an gameplay.mp4`
(`-an` drops the audio track), or track it with Git LFS.
