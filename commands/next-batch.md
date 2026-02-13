---
allowed-tools: Bash, Read, Write, Edit, Task, Glob, Grep, WebFetch, WebSearch
---

# 다음 PDF 배치 변환 (공유 큐)

공유 큐에서 다음 작업을 원자적으로 할당받아 변환합니다.
여러 터미널에서 동시에 실행해도 안전합니다 — 각 인스턴스가 서로 다른 작업을 자동으로 할당받습니다.

## 경로 설정

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
```

## 사용법

### 인자 없이 실행: 다음 10개 할당
```
/next-batch
```

### 숫자 인자: 해당 개수만큼 할당
```
/next-batch 5
```

## 실행 단계

### 1. 공유 큐에서 작업 할당

```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
RESULT=$(bash "$QUEUE_SCRIPT" claim ${ARGUMENTS:-10})
```

출력 파싱:
- 첫 줄 `CLAIMED:N` → 할당 성공, 이후 줄이 파일명
- `NO_TASKS_AVAILABLE` → 큐에 대기 작업 없음

### 2. 병렬 에이전트 실행

할당받은 각 파일에 대해 Task 도구로 백그라운드 에이전트 실행:

```
PDF 파일을 마크다운으로 변환하세요.

PDF: $PDF_DIR/[파일명].pdf
저장: $MD_DIR/[파일명].md

작업:
1. Read로 PDF 읽기
2. 마크다운 변환 (# 제목, ### 조항, **용어**, 표)
3. Write로 저장
4. 이미지 추출:
   Bash: python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/extract_images.py" "$PDF_DIR/[파일명].pdf" -o "$IMG_DIR" -v
5. 검증:
   Bash: python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/verify_markdown.py" "$PDF_DIR/[파일명].pdf" "$MD_DIR/[파일명].md" -v
6. 완료 시:
   Bash: bash "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/queue_manager.sh" complete "[파일명]"
7. 실패 시:
   Bash: bash "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/queue_manager.sh" fail "[파일명]" "에러 설명"
```

### 3. 상태 보고

에이전트 실행 후:
```bash
bash "$QUEUE_SCRIPT" status
```

## 에이전트 완료 시

에이전트 완료 알림을 받으면 `/next-batch 1`로 다음 1개를 즉시 할당하여
항상 10개 에이전트가 병렬 실행되도록 유지하세요.

## 멀티 인스턴스 동시 실행

- 큐 초기화(`init`)가 이미 완료된 상태에서 바로 실행 가능 (다른 터미널에서 `init` 불필요)
- `mv` 명령의 원자성으로 동일 작업 중복 할당 방지
- 세션 종료 시 미완료 작업은 pending/으로 자동 반환
