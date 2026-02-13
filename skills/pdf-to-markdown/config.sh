#!/bin/bash
# PDF → 마크다운 변환 플러그인 설정
# 새 프로젝트에서 사용 시 이 파일의 경로만 수정하면 됩니다.

# 프로젝트 루트 (자동 감지)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

# 플러그인 루트 (자동 감지)
PLUGIN_DIR="${CLAUDE_PLUGIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# PDF/마크다운 경로
PDF_DIR="$PROJECT_DIR/KR_강선규칙_2025/분할"
MD_DIR="$PROJECT_DIR/KR_강선규칙_2025/마크다운"
IMG_DIR="$MD_DIR/images"

# --- 공유 큐 설정 (디렉토리 기반) ---
QUEUE_DIR="$PROJECT_DIR/.claude/queue"
QUEUE_PENDING="$QUEUE_DIR/pending"
QUEUE_PROCESSING="$QUEUE_DIR/processing"
QUEUE_DONE="$QUEUE_DIR/done"
QUEUE_FAILED="$QUEUE_DIR/failed"

# 레거시 큐 파일 (마이그레이션용)
QUEUE_FILE_LEGACY="$PROJECT_DIR/.claude/pdf-queue.txt"

# 인스턴스 식별자 (호스트명 + PID)
INSTANCE_ID="$(hostname -s)_pid-$$"

# stale 작업 기준 (초, 기본 30분)
STALE_THRESHOLD=1800

# 스킬 디렉토리
SKILL_DIR="$PLUGIN_DIR/skills/pdf-to-markdown"

# 큐 관리 스크립트
QUEUE_SCRIPT="$SKILL_DIR/scripts/queue_manager.sh"
