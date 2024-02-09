# Requirement
bash, bc, file, sort, uniq, tr, sed
# Usage
This script will only generate command.
Warning messages can be redirected to `/dev/null` if you don't want to see.

If you want to run generated command directly, you can try
`bash <(./parse_cue2flac.sh sheet.cue 2>/dev/null)`.
```
./parse_cue2flac.sh sheet.cue [-t track] [-f format]

sheet.cue: Cue sheet to be parse.

Available Options:
-h: This message. 
-t: Specific the track(s) to be extracted.
    e.g. 
      cue_split.sh sheet.cue -t 1
      cue_split.sh sheet.cue -t 3,4,2
-f: Specific format (pass to ffmpeg).
    (default will be flac)
```
