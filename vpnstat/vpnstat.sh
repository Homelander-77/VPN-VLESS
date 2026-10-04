#!/usr/bin/env bash
# ============================================================
# vpnstat — статистика трафика xray по устройствам
#
#   vpnstat                 текущий месяц (сохранённое + живые счётчики)
#   vpnstat 2026-09         конкретный месяц
#   vpnstat months          итоги по месяцам
#   vpnstat today           сегодня по устройствам
#   vpnstat yesterday       вчера по устройствам
#   vpnstat 2026-10-04      конкретный день
#   vpnstat days [N]        итоги за последние N дней (по умолчанию 14)
#   vpnstat live [сек]      скорость прямо сейчас, обновляется (Ctrl+C — выход)
#   vpnstat install         копить статистику: cron раз в 10 мин + сохранение
#                           при остановке xray (иначе счётчики живут до перезапуска)
#   vpnstat uninstall       убрать cron и хук (сохранённые данные остаются)
#   vpnstat save            забрать счётчики xray в файл месяца (это делает cron)
#
# Устройство = клиент с полем "email" в конфиге сервера.
# Нужны секции stats / api (127.0.0.1:10085) / policy в конфиге xray.
# Данные: /var/lib/vpnstat/ГГГГ-ММ.tsv и days/ГГГГ-ММ-ДД.tsv (только root).
# ============================================================
set -uo pipefail

API="${VPNSTAT_API:-127.0.0.1:10085}"
XRAY="${XRAY:-$(command -v xray 2>/dev/null || echo /usr/local/bin/xray)}"
DIR="${VPNSTAT_DIR:-/var/lib/vpnstat}"
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
CRON_FILE=/etc/cron.d/vpnstat
HOOK_FILE=/etc/systemd/system/xray.service.d/vpnstat.conf
MONTHS=(январь февраль март апрель май июнь июль август сентябрь октябрь ноябрь декабрь)
MONTHS_GEN=(января февраля марта апреля мая июня июля августа сентября октября ноября декабря)

if [ -t 1 ]; then
  B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' C=$'\e[36m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'
else
  B= D= G= C= Y= R= N=
fi

die() { echo "${R}$*${N}" >&2; exit 1; }

# данные доступны только root — перезапускаемся через sudo
need_root() {
  if [ "$(id -u)" -ne 0 ] && [ -z "${VPNSTAT_DIR:-}" ]; then
    exec sudo -- "$SELF" "$@"
  fi
}

# ---------- данные ----------

# живые счётчики xray → «имя<TAB>отдано<TAB>получено» (байты)
# аргумент -reset — обнулить счётчики после чтения
query() {
  local raw
  if ! raw=$("$XRAY" api statsquery --server="$API" -pattern 'user>>>' "$@" 2>&1); then
    echo "${R}Не получилось взять статистику у xray ($API):${N}" >&2
    echo "  $raw" >&2
    echo "  Проверь: systemctl status xray, и что в конфиге есть stats / api / policy." >&2
    return 1
  fi
  # нулевые значения xray опускает — тогда счётчик просто остаётся 0
  # JSON может прийти как в несколько строк, так и одной — режем по { } ,
  printf '%s\n' "$raw" | tr '{},' '\n\n\n' | awk -F'"' '
    /"name"/  { split($4, a, ">>>"); n = a[2]; d = a[4]; u[n] = 1 }
    /"value"/ { v = $0; gsub(/[^0-9]/, "", v); t[n, d] = v }
    END { for (k in u) if (k != "") printf "%s\t%.0f\t%.0f\n", k, t[k, "uplink"], t[k, "downlink"] }'
}

# сложить строки с одинаковым именем
merge() {
  awk -F'\t' 'NF >= 3 { u[$1] += $2; d[$1] += $3 }
    END { for (k in u) printf "%s\t%.0f\t%.0f\n", k, u[k], d[k] }'
}

# ---------- вывод ----------

# дополнить пробелами до ширины в символах (а не байтах — для кириллицы)
pad()  { local s=$1 n=$(( $2 - ${#1} )); printf '%s%*s' "$s" $(( n > 0 ? n : 0 )) ''; }
lpad() { local s=$1 n=$(( $2 - ${#1} )); printf '%*s%s' $(( n > 0 ? n : 0 )) '' "$s"; }

# stdin: «имя<TAB>отдано<TAB>получено»; $1 — заголовок, $2 — суффикс единиц («/с»)
# $3 — подпись первой колонки; $4 = bydate — по порядку имён (даты), а не по объёму
render() {
  local title=$1 sfx=${2:-} head=${3:-УСТРОЙСТВО} order=${4:-} rows w=10 name up down tot pct bar
  rows=$(awk -F'\t' -v sfx="$sfx" '
    function h(b) {
      if (b >= 1099511627776) return sprintf("%.2f TB%s", b / 1099511627776, sfx)
      if (b >= 1073741824)    return sprintf("%.2f GB%s", b / 1073741824, sfx)
      if (b >= 1048576)       return sprintf("%.1f MB%s", b / 1048576, sfx)
      if (b >= 1024)          return sprintf("%.0f KB%s", b / 1024, sfx)
      return sprintf("%d B%s", b, sfx)
    }
    NF >= 3 { i++; n[i] = $1; u[i] = $2; d[i] = $3; t[i] = $2 + $3; all += t[i]; su += $2; sd += $3 }
    END {
      for (k = 1; k <= i; k++) {
        p = all ? t[k] / all : 0; f = int(p * 20 + 0.5); b = ""
        for (j = 0; j < 20; j++) b = b (j < f ? "█" : "░")
        printf "%s\t%s\t%s\t%s\t%.0f%%\t%s\t%.0f\n", n[k], h(u[k]), h(d[k]), h(t[k]), p * 100, b, t[k]
      }
      if (i) printf "ИТОГО\t%s\t%s\t%s\t-\t-\t-1\n", h(su), h(sd), h(all)
    }' | sort -t$'\t' -k7,7nr)
  if [ "$order" = bydate ] && [ -n "$rows" ]; then
    rows=$(grep -v $'^ИТОГО\t' <<< "$rows" | sort; grep $'^ИТОГО\t' <<< "$rows")
  fi

  echo
  echo "  ${B}${title}${N}"
  if [ -z "$rows" ]; then
    echo "  ${D}нет данных — устройства ещё не подключались${N}"
    echo
    return
  fi

  while IFS=$'\t' read -r name _; do
    [ ${#name} -gt $w ] && w=${#name}
  done <<< "$rows"

  local line
  line=$(printf '%*s' $(( w + 70 )) '' | tr ' ' '-')
  printf '  %s%s  %s  %s  %s   %s%s\n' "$D" "$(pad "$head" "$w")" \
    "$(lpad '↑ ОТДАНО' 12)" "$(lpad '↓ ПОЛУЧЕНО' 12)" "$(lpad 'ВСЕГО' 12)" "ДОЛЯ" "$N"
  echo "  ${D}${line}${N}"

  while IFS=$'\t' read -r name up down tot pct bar _; do
    if [ "$pct" = "-" ]; then
      echo "  ${D}${line}${N}"
      printf '  %s%s  %s  %s  %s%s\n' "$B" "$(pad "$name" "$w")" \
        "$(lpad "$up" 12)" "$(lpad "$down" 12)" "$(lpad "$tot" 12)" "$N"
    else
      printf '  %s%s%s  %s  %s  %s%s%s   %s %s%s%s\n' "$C" "$(pad "$name" "$w")" "$N" \
        "$(lpad "$up" 12)" "$(lpad "$down" 12)" "$B" "$(lpad "$tot" 12)" "$N" \
        "$(lpad "$pct" 4)" "$G" "$bar" "$N"
    fi
  done <<< "$rows"
  echo
}

xray_since() {
  local ts
  ts=$(systemctl show xray -p ActiveEnterTimestamp --value 2>/dev/null)
  [ -n "$ts" ] && date -d "$ts" '+%d.%m %H:%M' 2>/dev/null
}

month_title() {
  local m=$1
  echo "${MONTHS[$(( 10#${m#*-} - 1 ))]} ${m%-*}"
}

# ---------- команды ----------

show_month() {
  local m=${1:-$(date +%Y-%m)} f live="" title
  f="$DIR/$m.tsv"
  if [ "$m" = "$(date +%Y-%m)" ]; then
    live=$(query) || exit 1
  elif [ ! -f "$f" ]; then
    die "За $m данных нет."
  fi

  if [ -f "$CRON_FILE" ] || [ -f "$f" ]; then
    title="Трафик VPN · $(month_title "$m")"
  else
    local since
    since=$(xray_since)
    title="Трафик VPN · с перезапуска xray${since:+ ($since)}"
  fi

  { [ -f "$f" ] && cat "$f"; [ -n "$live" ] && printf '%s\n' "$live"; true; } | merge | render "$title"

  if [ -f "$CRON_FILE" ]; then
    echo "  ${D}xray работает с $(xray_since || echo '?') · статистика копится каждые 10 мин${N}"
  else
    echo "  ${Y}Счётчики xray обнуляются при перезапуске. Чтобы копить по месяцам: vpnstat install${N}"
  fi
  echo
}

show_months() {
  local f m rows="" cur
  cur=$(date +%Y-%m)
  for f in "$DIR"/*.tsv; do
    [ -e "$f" ] || continue
    m=$(basename "$f" .tsv)
    rows+="$(awk -F'\t' -v m="$m" '{ u += $2; d += $3 } END { printf "%s\t%.0f\t%.0f", m, u, d }' "$f")"$'\n'
  done
  # текущий месяц — с живыми счётчиками
  if live=$(query 2>/dev/null) && [ -n "$live" ]; then
    rows+="$(printf '%s\n' "$live" | awk -F'\t' -v m="$cur" '{ u += $2; d += $3 } END { printf "%s\t%.0f\t%.0f", m, u, d }')"$'\n'
  fi
  [ -n "$rows" ] || die "Истории пока нет. Включи накопление: vpnstat install"
  printf '%s' "$rows" | merge | render "Трафик VPN по месяцам" "" "МЕСЯЦ" bydate
}

live() {
  local iv=${1:-2} a b rates
  [[ $iv =~ ^[0-9]+$ ]] && [ "$iv" -gt 0 ] || die "Интервал — целое число секунд."
  a=$(query) || exit 1
  trap 'printf "\e[?25h\n"; exit 0' INT TERM
  printf '\e[?25l'
  while sleep "$iv"; do
    b=$(query) || exit 1
    # скорость = прирост счётчиков за интервал; отрицательный (сброс) → 0
    rates=$(printf '%s\n' "$b" | PREV="$a" awk -F'\t' -v iv="$iv" '
      BEGIN { n = split(ENVIRON["PREV"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], f, "\t"); pu[f[1]] = f[2]; pd[f[1]] = f[3] } }
      NF >= 3 { du = $2 - pu[$1]; dd = $3 - pd[$1]; if (du < 0) du = 0; if (dd < 0) dd = 0
                printf "%s\t%.0f\t%.0f\n", $1, du / iv, dd / iv }')
    printf '\e[H\e[2J'
    printf '%s\n' "$rates" | render "Скорость сейчас · $(date '+%H:%M:%S') · обновление каждые ${iv} с" "/с"
    echo "  ${D}Ctrl+C — выход${N}"
    a=$b
  done
}

day_title() {
  local d=$1
  echo "$(( 10#${d:8:2} )) ${MONTHS_GEN[$(( 10#${d:5:2} - 1 ))]} ${d:0:4}"
}

show_day() {
  local d=$1 f live=""
  f="$DIR/days/$d.tsv"
  if [ "$d" = "$(date +%F)" ]; then
    live=$(query) || exit 1
  elif [ ! -f "$f" ]; then
    die "За $d данных нет (по дням копится только после vpnstat install)."
  fi
  { [ -f "$f" ] && cat "$f"; [ -n "$live" ] && printf '%s\n' "$live"; true; } | merge | render "Трафик VPN · $(day_title "$d")"
  [ -f "$CRON_FILE" ] || echo "  ${Y}По дням статистика копится только после: vpnstat install${N}"
  echo
}

show_days() {
  local n=${1:-14} f d rows="" today
  [[ $n =~ ^[0-9]+$ ]] && [ "$n" -gt 0 ] || die "Число дней — целое число."
  today=$(date +%F)
  for f in $(ls "$DIR/days/"*.tsv 2>/dev/null | sort | tail -n "$n"); do
    d=$(basename "$f" .tsv)
    rows+="$(awk -F'\t' -v d="$d" '{ u += $2; d2 += $3 } END { printf "%s\t%.0f\t%.0f", d, u, d2 }' "$f")"$'\n'
  done
  # сегодня — с живыми счётчиками
  if live=$(query 2>/dev/null) && [ -n "$live" ]; then
    rows+="$(printf '%s\n' "$live" | awk -F'\t' -v d="$today" '{ u += $2; d2 += $3 } END { printf "%s\t%.0f\t%.0f", d, u, d2 }')"$'\n'
  fi
  [ -n "$rows" ] || die "Истории по дням пока нет. Включи накопление: vpnstat install"
  printf '%s' "$rows" | merge | sort | tail -n "$n" | render "Трафик VPN · последние $n дн." "" "ДЕНЬ" bydate
}

save() {
  local f cur
  umask 077
  mkdir -p "$DIR" && chmod 700 "$DIR"
  if command -v flock >/dev/null; then
    exec 9>"$DIR/.lock"
    flock -w 30 9 || die "Не дождался блокировки $DIR/.lock"
  fi
  cur=$(query -reset) || exit 1
  [ -n "$cur" ] || exit 0
  mkdir -p "$DIR/days"
  for f in "$DIR/$(date +%Y-%m).tsv" "$DIR/days/$(date +%F).tsv"; do
    { [ -f "$f" ] && cat "$f"; printf '%s\n' "$cur"; } | merge > "$f.tmp" && mv "$f.tmp" "$f"
  done
}

install_hooks() {
  [ "$SELF" = /usr/local/bin/vpnstat ] || die "Сначала положи скрипт в /usr/local/bin/vpnstat"
  mkdir -p "$DIR" && chmod 700 "$DIR"
  # 23:59 — чтобы трафик последних минут дня не уехал в следующий
  printf '%s\n' "*/10 * * * * root /usr/local/bin/vpnstat save >/dev/null 2>&1" \
                "59 23 * * * root /usr/local/bin/vpnstat save >/dev/null 2>&1" > "$CRON_FILE"
  chmod 644 "$CRON_FILE"
  # при остановке/перезапуске xray сначала забрать счётчики, потом гасить
  mkdir -p "$(dirname "$HOOK_FILE")"
  printf '[Service]\nExecStop=-/usr/local/bin/vpnstat save\n' > "$HOOK_FILE"
  systemctl daemon-reload
  /usr/local/bin/vpnstat save
  echo "${G}Готово:${N} статистика сохраняется каждые 10 минут и при остановке xray."
  echo "Данные: $DIR"
}

uninstall_hooks() {
  rm -f "$CRON_FILE" "$HOOK_FILE"
  systemctl daemon-reload
  echo "Cron и хук убраны. Сохранённые данные остались в $DIR"
}

usage() { sed -n '3,20p' "$SELF" | sed 's/^# \{0,1\}//'; }

# ---------- запуск ----------

cmd=${1:-}
case $cmd in
  -h|--help|help) usage; exit 0 ;;
esac
need_root "$@"

case $cmd in
  "")             show_month ;;
  months|history) show_months ;;
  today)          show_day "$(date +%F)" ;;
  yesterday)      show_day "$(date -d yesterday +%F 2>/dev/null || date -v-1d +%F)" ;;
  days)           show_days "${2:-14}" ;;
  live)           live "${2:-2}" ;;
  save)           save ;;
  install)        install_hooks ;;
  uninstall)      uninstall_hooks ;;
  *)
    if [[ $cmd =~ ^[0-9]{4}-(0[1-9]|1[0-2])$ ]]; then
      show_month "$cmd"
    elif [[ $cmd =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; then
      show_day "$cmd"
    else
      usage; exit 1
    fi
    ;;
esac
