#!/usr/bin/env bash
help(){
cat << EOF
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
EOF
}

# cue sheet use mm:ss:ff (minute-second-frame) format, and 75fps.
# to_second(){
#   local mm ss ff IFS=':'
#   read -r mm ss ff <<< "$1"
#   echo -e "scale=4;$mm * 60 + $ss + $ff / 75" | bc
# }
parse_main_section(){
  local key value="${line#* \"}"
  if [ "$value" = "$line" ]; then
    value="${line##*\ }"
    key="${line%\ *}"
  else
    value="${value%\"*}"
    key="${line%% \"*}"
  fi
  case "$key" in
    'REM GENRE')
      GENERAL_GENRE="$value"
    ;;
    'REM DATE')
      GENERAL_DATE="$value"
    ;;
    'PERFORMER')
      GENERAL_PERFORMER="$value"
    ;;
    'TITLE')
      GENERAL_TITLE="$value"
    ;;
    'FILE')
      GENERAL_FILE="$value"
    ;;
    *)
      echo "main unhandled:$line" >&2
      echo "  current key:$key" >&2
      echo "  current value:$value" >&2
    ;;
  esac
}

parse_track_section(){
  local buffer="${line#* \"}"
  local key="${line%%\"*}"
  case "${key%\ *}" in
    '    TITLE')
      TITLE[$audio_track_num]="${buffer%\"}"
    ;;
    '    PERFORMER')
      PERFORMER[$audio_track_num]="${buffer%\"}"
    ;;
    '    SONGWRITER')
      SONGWRITER[$audio_track_num]="${buffer%\"}"
    ;;
    '    INDEX 01')
      INDEX01[$audio_track_num]="${line##*\ }"
    ;;
    '    INDEX 00')
      INDEX00[$audio_track_num]="${line##*\ }"
    ;;
    *)
      echo "track unhandled:$line" >&2
      echo "  current buffer:$buffer" >&2
      echo "  current key:${line%\ *}" >&2
    ;;
  esac
}

parse_start(){
  local IFS
  # set IFS
  [ -z ${isCRLF+x} ] && IFS=$'\n' || IFS=$'\r\n' 
  # track num count
  audio_track_num=0
  while read -r line; do
    if [ ! -z ${withBOM+x} ]; then
      # echo "handle BOM" 
      line=${line#$'\xef\xbb\xbf'}
      unset withBOM
    fi
    # perform Track section parsing
    if [ ! "${line#  TRACK }" = "$line" ]; then
      if [ ! "${line% AUDIO}" = "$line" ]; then
        Main_Section=''
        ((audio_track_num++))
      fi
    elif [ $audio_track_num -gt 0 ]; then
      parse_track_section
    # perform Main section parsing
    elif [ -z ${Main_Section+x} ]; then
      parse_main_section
    fi
  done < "$cue_sheet"
}

ffmpeg_cmd_construct(){
  [ -z ${INDEX00[$i]+x} ] \
    && filter_complex_cmd+=("[0:a]atrim=start=${INDEX01[$i]}[a$i];") \
    || filter_complex_cmd+=("[0:a]atrim=start=${INDEX01[$i]}:end=${INDEX00[$i]}[a$i];")

  ffmpeg_section2_args+=("-map \"[a$i]\"")
  [ -z ${PERFORMER[$i]+x} ] || ffmpeg_section2_args+=("-metadata performer=\"${PERFORMER[$i]}\"")
  [ -z ${SONGWRITER[$i]+x} ] || ffmpeg_section2_args+=("-metadata composer=\"${SONGWRITER[$i]}\"")
  [ -z ${GENERAL_DATE+x} ] || ffmpeg_section2_args+=("-metadata date=\"$GENERAL_DATE\"")
  ffmpeg_section2_args+=("-metadata title=\"${TITLE[$i]}\"")
  ffmpeg_section2_args+=("-metadata album=\"$GENERAL_TITLE\"")
  ffmpeg_section2_args+=("-metadata track=\"$i/$audio_track_num\"")
  ffmpeg_section2_args+=("-metadata TRACKTOTAL=\"$audio_track_num\"")
  [ ${#i} -eq 1 ] \
    && ffmpeg_section2_args+=("\"0$i. ${TITLE[$i]}.$extend_format\"") \
    || ffmpeg_section2_args+=("\"$i. ${TITLE[$i]}.$extend_format\"")
}

# check if the file extension is cue
filename=$1
if [ ! "${filename##*.}" = 'cue' ]; then
  echo "Require cue as file extension!"
  exit 1
fi
# check CRLF
file_report=`file "$filename"`
[ "${file_report#*CRLF}" != "$file_report" ] && isCRLF=1
[ "${file_report#*BOM}" != "$file_report" ] && withBOM=1
cue_sheet="$filename"
shift 1

# main
while getopts t:f: opt; do
  case $opt in
    h)
      help
      exit 1
      ;;
    t)
      tracks=(`echo "$OPTARG," | sed 's/,/ \n/g' | sort | uniq | tr -d '\n'`)
      # echo "tracks=${tracks[0]}"
      # echo "Num of tracks to be extracted = ${#tracks[@]}"
      ;;
    f)
      extend_format=$OPTARG
      ;;
  esac
done

parse_start
# extend_format=${extend_format:-"${GENERAL_FILE##*.}"}
extend_format=${extend_format:-"flac"}
# echo "extend_format=$extend_format"
# echo "$audio_track_num audio track(s) found."

# cue sheet use mm:ss:ff (minute-second-frame) format, and 75fps.
# convert to second
INDEX01=('' `echo "scale=4;60*${INDEX01[*]}/75" | sed 's/ /\/75;60*/g;s/:/+/g' | bc `)
[ -z ${INDEX00+x} ] \
  && INDEX00=('' `echo "scale=4;60*${INDEX00[*]}/75" | sed 's/ /\/75;60*/g;s/:/+/g' | bc `) \
  || INDEX00=(${INDEX01[*]})

# construct ffmpeg command
# appending array seems faster then string concatenation
ffmpeg_section1_args=('-i' "\"$GENERAL_FILE\"" '-filter_complex')
filter_complex_cmd=('"')
ffmpeg_section2_args=

if [ -z ${tracks+x} ]; then
  for ((i=1; i<=$audio_track_num; i++)); do
    ffmpeg_cmd_construct
  done
else
  for i in "${tracks[@]}"; do
    ffmpeg_cmd_construct
  done
fi

filter_complex_cmd+=('"')
echo "ffmpeg ${ffmpeg_section1_args[@]} ${filter_complex_cmd[@]} ${ffmpeg_section2_args[@]}"
# echo "\
#   $GENERAL_TITLE
#   $GENERAL_PERFORMER
#   $GENERAL_GENRE
#   $GENERAL_DATE
#   $GENERAL_FILE"
