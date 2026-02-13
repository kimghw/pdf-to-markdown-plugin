#!/bin/bash
# queue_manager.sh - 디렉토리 기반 공유 큐 관리 스크립트
# 여러 Claude Code 인스턴스가 클라우드 저장소를 통해 안전하게 병렬 작업할 수 있도록 합니다.
#
# 사용법: bash queue_manager.sh <command> [args...]
#
# Commands:
#   init              큐 디렉토리 생성 및 pending/ 에 미변환 PDF 등록
#   migrate           레거시 pdf-queue.txt를 디렉토리 기반으로 이전
#   claim [N]         pending/에서 N개(기본 1) 원자적 할당
#   complete <name>   작업 완료 (processing/ → done/)
#   fail <name> [msg] 작업 실패 (processing/ → failed/)
#   release <name>    작업 반환 (processing/ → pending/)
#   recover           stale 작업 복구 (30분 초과)
#   status            전체 현황 출력
#   list <state>      특정 상태의 작업 목록 (pending|processing|done|failed)

set -euo pipefail

# 설정 로드
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config.sh"

COMMAND="${1:-}"
shift || true

# --- 헬퍼 함수 ---

now_iso() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_epoch() {
    date +%s
}

ensure_dirs() {
    mkdir -p "$QUEUE_PENDING" "$QUEUE_PROCESSING" "$QUEUE_DONE" "$QUEUE_FAILED"
}

task_file_name() {
    local name="$1"
    echo "${name%.task}.task"
}

create_task_file() {
    local name="$1"
    local dest="$2"
    local taskfile="$dest/$(task_file_name "$name")"
    cat > "$taskfile" <<EOF
pdf=${name}.pdf
created_at=$(now_iso)
claimed_by=
claimed_at=
completed_at=
error=
EOF
}

update_task_field() {
    local file="$1"
    local field="$2"
    local value="$3"
    if grep -q "^${field}=" "$file" 2>/dev/null; then
        sed -i "s|^${field}=.*|${field}=${value}|" "$file"
    else
        echo "${field}=${value}" >> "$file"
    fi
}

read_task_field() {
    local file="$1"
    local field="$2"
    grep "^${field}=" "$file" 2>/dev/null | head -1 | cut -d'=' -f2-
}

# --- 명령어 ---

cmd_init() {
    ensure_dirs

    # 레거시 큐 파일 감지
    if [ -f "$QUEUE_FILE_LEGACY" ] && [ -s "$QUEUE_FILE_LEGACY" ]; then
        echo "WARNING: 레거시 큐 파일 감지 ($QUEUE_FILE_LEGACY)"
        echo "  'bash $QUEUE_SCRIPT migrate' 로 이전할 수 있습니다."
        echo ""
    fi

    local added=0
    local skipped=0

    for pdf in "$PDF_DIR"/*.pdf; do
        [ -f "$pdf" ] || continue
        local basename
        basename=$(basename "$pdf" .pdf)
        local taskname
        taskname=$(task_file_name "$basename")
        local md="$MD_DIR/${basename}.md"

        # 이미 변환된 경우
        if [ -f "$md" ]; then
            local size
            size=$(stat -c%s "$md" 2>/dev/null || stat -f%z "$md" 2>/dev/null || echo 0)
            if [ "$size" -ge 1000 ]; then
                # 다른 상태에 있으면 done으로 이동
                if [ -f "$QUEUE_PENDING/$taskname" ]; then
                    mv "$QUEUE_PENDING/$taskname" "$QUEUE_DONE/$taskname"
                elif [ -f "$QUEUE_PROCESSING/$taskname" ]; then
                    mv "$QUEUE_PROCESSING/$taskname" "$QUEUE_DONE/$taskname"
                fi
                # done에 없으면 생성
                if [ ! -f "$QUEUE_DONE/$taskname" ]; then
                    create_task_file "$basename" "$QUEUE_DONE"
                    update_task_field "$QUEUE_DONE/$taskname" "completed_at" "$(now_iso)"
                    update_task_field "$QUEUE_DONE/$taskname" "claimed_by" "pre-existing"
                fi
                skipped=$((skipped + 1))
                continue
            fi
        fi

        # 이미 큐에 있는 경우
        if [ -f "$QUEUE_PENDING/$taskname" ] || \
           [ -f "$QUEUE_PROCESSING/$taskname" ] || \
           [ -f "$QUEUE_DONE/$taskname" ] || \
           [ -f "$QUEUE_FAILED/$taskname" ]; then
            skipped=$((skipped + 1))
            continue
        fi

        # 새 작업 등록
        create_task_file "$basename" "$QUEUE_PENDING"
        added=$((added + 1))
    done

    # 이미지 디렉토리 생성
    mkdir -p "$IMG_DIR"

    echo "=== 큐 초기화 완료 ==="
    echo "추가: ${added}개"
    echo "스킵 (이미 등록/변환됨): ${skipped}개"
    echo ""
    cmd_status
}

cmd_migrate() {
    ensure_dirs

    if [ ! -f "$QUEUE_FILE_LEGACY" ]; then
        echo "레거시 큐 파일이 없습니다: $QUEUE_FILE_LEGACY"
        return 0
    fi

    local migrated=0
    while IFS= read -r name; do
        [ -z "$name" ] && continue
        local taskname
        taskname=$(task_file_name "$name")

        if [ ! -f "$QUEUE_PENDING/$taskname" ] && \
           [ ! -f "$QUEUE_PROCESSING/$taskname" ] && \
           [ ! -f "$QUEUE_DONE/$taskname" ] && \
           [ ! -f "$QUEUE_FAILED/$taskname" ]; then
            create_task_file "$name" "$QUEUE_PENDING"
            migrated=$((migrated + 1))
        fi
    done < "$QUEUE_FILE_LEGACY"

    mv "$QUEUE_FILE_LEGACY" "${QUEUE_FILE_LEGACY}.migrated"

    echo "이전 완료: ${migrated}개"
    echo "레거시 파일 이름 변경: ${QUEUE_FILE_LEGACY}.migrated"
}

cmd_claim() {
    local count="${1:-1}"
    local claimed=0
    local claimed_list=""

    # stale 작업 자동 복구
    _do_recover 0

    # pending 파일 순회 (glob은 기본적으로 정렬됨)
    for taskfile in "$QUEUE_PENDING"/*.task; do
        [ -f "$taskfile" ] || continue
        [ "$claimed" -ge "$count" ] && break

        local taskname
        taskname=$(basename "$taskfile")
        local base="${taskname%.task}"

        # mv로 원자적 할당 시도
        if mv "$taskfile" "$QUEUE_PROCESSING/$taskname" 2>/dev/null; then
            update_task_field "$QUEUE_PROCESSING/$taskname" "claimed_by" "$INSTANCE_ID"
            update_task_field "$QUEUE_PROCESSING/$taskname" "claimed_at" "$(now_iso)"
            claimed=$((claimed + 1))
            claimed_list="${claimed_list}${base}"$'\n'
        fi
    done

    if [ "$claimed" -eq 0 ]; then
        echo "NO_TASKS_AVAILABLE"
    else
        echo "CLAIMED:${claimed}"
        printf "%s" "$claimed_list"
    fi
}

cmd_complete() {
    local name="$1"
    local taskname
    taskname=$(task_file_name "$name")
    local src="$QUEUE_PROCESSING/$taskname"
    local dst="$QUEUE_DONE/$taskname"

    if [ ! -f "$src" ]; then
        echo "ERROR: $name 이 processing/에 없습니다"
        return 1
    fi

    update_task_field "$src" "completed_at" "$(now_iso)"
    mv "$src" "$dst"
    echo "COMPLETED:$name"
}

cmd_fail() {
    local name="$1"
    local msg="${2:-unknown error}"
    local taskname
    taskname=$(task_file_name "$name")
    local src="$QUEUE_PROCESSING/$taskname"
    local dst="$QUEUE_FAILED/$taskname"

    if [ ! -f "$src" ]; then
        echo "ERROR: $name 이 processing/에 없습니다"
        return 1
    fi

    update_task_field "$src" "error" "$msg"
    update_task_field "$src" "completed_at" "$(now_iso)"
    mv "$src" "$dst"
    echo "FAILED:$name ($msg)"
}

cmd_release() {
    local name="$1"
    local taskname
    taskname=$(task_file_name "$name")
    local src="$QUEUE_PROCESSING/$taskname"
    local dst="$QUEUE_PENDING/$taskname"

    if [ ! -f "$src" ]; then
        echo "ERROR: $name 이 processing/에 없습니다"
        return 1
    fi

    update_task_field "$src" "claimed_by" ""
    update_task_field "$src" "claimed_at" ""
    mv "$src" "$dst"
    echo "RELEASED:$name"
}

cmd_recover() {
    _do_recover 1
}

_do_recover() {
    local verbose="${1:-1}"
    local now
    now=$(now_epoch)
    local recovered=0

    for taskfile in "$QUEUE_PROCESSING"/*.task; do
        [ -f "$taskfile" ] || continue

        local taskname
        taskname=$(basename "$taskfile")
        local basename="${taskname%.task}"

        # 마크다운 파일이 이미 존재하면 → 완료 처리
        local md="$MD_DIR/${basename}.md"
        if [ -f "$md" ]; then
            local size
            size=$(stat -c%s "$md" 2>/dev/null || stat -f%z "$md" 2>/dev/null || echo 0)
            if [ "$size" -ge 1000 ]; then
                update_task_field "$taskfile" "completed_at" "$(now_iso)"
                mv "$taskfile" "$QUEUE_DONE/$taskname"
                [ "$verbose" -eq 1 ] && echo "RECOVERED (완료됨): $basename"
                recovered=$((recovered + 1))
                continue
            fi
        fi

        # claim 타임스탬프 확인
        local claimed_at
        claimed_at=$(read_task_field "$taskfile" "claimed_at")
        if [ -z "$claimed_at" ]; then
            update_task_field "$taskfile" "claimed_by" ""
            mv "$taskfile" "$QUEUE_PENDING/$taskname"
            [ "$verbose" -eq 1 ] && echo "RECOVERED (미할당): $basename"
            recovered=$((recovered + 1))
            continue
        fi

        # 시간 기반 stale 판단
        local claimed_epoch
        claimed_epoch=$(date -d "$claimed_at" +%s 2>/dev/null || echo 0)

        local age=$((now - claimed_epoch))
        if [ "$age" -gt "$STALE_THRESHOLD" ]; then
            update_task_field "$taskfile" "claimed_by" ""
            update_task_field "$taskfile" "claimed_at" ""
            mv "$taskfile" "$QUEUE_PENDING/$taskname"
            [ "$verbose" -eq 1 ] && echo "RECOVERED (stale, ${age}초): $basename"
            recovered=$((recovered + 1))
        fi
    done

    if [ "$verbose" -eq 1 ]; then
        echo "복구됨: ${recovered}개"
    fi
}

cmd_status() {
    ensure_dirs

    local pending=0 processing=0 done_count=0 failed=0 total_pdf=0

    for f in "$QUEUE_PENDING"/*.task; do [ -f "$f" ] && pending=$((pending + 1)); done
    for f in "$QUEUE_PROCESSING"/*.task; do [ -f "$f" ] && processing=$((processing + 1)); done
    for f in "$QUEUE_DONE"/*.task; do [ -f "$f" ] && done_count=$((done_count + 1)); done
    for f in "$QUEUE_FAILED"/*.task; do [ -f "$f" ] && failed=$((failed + 1)); done
    for f in "$PDF_DIR"/*.pdf; do [ -f "$f" ] && total_pdf=$((total_pdf + 1)); done

    echo "=== 공유 큐 현황 ==="
    echo "총 PDF:     $total_pdf"
    echo "대기:       $pending"
    echo "작업중:     $processing"
    echo "완료:       $done_count"
    echo "실패:       $failed"

    local not_in_queue=$((total_pdf - pending - processing - done_count - failed))
    if [ "$not_in_queue" -gt 0 ]; then
        echo "미등록:     $not_in_queue"
    fi

    if [ "$processing" -gt 0 ]; then
        echo ""
        echo "=== 작업중 상세 ==="
        for taskfile in "$QUEUE_PROCESSING"/*.task; do
            [ -f "$taskfile" ] || continue
            local name
            name=$(basename "$taskfile" .task)
            local by
            by=$(read_task_field "$taskfile" "claimed_by")
            local at
            at=$(read_task_field "$taskfile" "claimed_at")
            echo "  $name  (by: $by, since: $at)"
        done
    fi

    if [ "$failed" -gt 0 ]; then
        echo ""
        echo "=== 실패 항목 ==="
        for taskfile in "$QUEUE_FAILED"/*.task; do
            [ -f "$taskfile" ] || continue
            local name
            name=$(basename "$taskfile" .task)
            local err
            err=$(read_task_field "$taskfile" "error")
            echo "  $name: $err"
        done
    fi
}

cmd_list() {
    local state="$1"
    local dir
    case "$state" in
        pending)    dir="$QUEUE_PENDING" ;;
        processing) dir="$QUEUE_PROCESSING" ;;
        done)       dir="$QUEUE_DONE" ;;
        failed)     dir="$QUEUE_FAILED" ;;
        *) echo "Unknown state: $state"; return 1 ;;
    esac

    for taskfile in "$dir"/*.task; do
        [ -f "$taskfile" ] || continue
        basename "$taskfile" .task
    done | sort
}

# --- 디스패치 ---

case "$COMMAND" in
    init)     cmd_init ;;
    migrate)  cmd_migrate ;;
    claim)    cmd_claim "$@" ;;
    complete) cmd_complete "$@" ;;
    fail)     cmd_fail "$@" ;;
    release)  cmd_release "$@" ;;
    recover)  cmd_recover ;;
    status)   cmd_status ;;
    list)     cmd_list "$@" ;;
    *)
        echo "사용법: queue_manager.sh <init|migrate|claim|complete|fail|release|recover|status|list>"
        exit 1
        ;;
esac
