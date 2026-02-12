---
allowed-tools: Bash, Read, Write, Edit, Task, Glob, Grep, WebFetch, WebSearch
---

# 다음 PDF 배치 변환

작업 큐에서 다음 PDF를 가져와 변환합니다.

## 경로 설정

모든 경로는 `$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh`에서 관리합니다.
```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
```

## 실행 방법

### 인자 없이 실행: 다음 10개 배치 실행
```
/next-batch
```

### 숫자 인자: 해당 개수만큼 실행
```
/next-batch 5
```

## 실행 단계

### 1. 큐에서 작업 가져오기

Bash로 큐 파일에서 다음 작업들을 가져오세요:
```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
head -$COUNT "$QUEUE_FILE"
```

($ARGUMENTS가 있으면 그 숫자만큼, 없으면 10개)

### 2. 병렬 에이전트 실행

가져온 각 파일에 대해 Task 도구로 백그라운드 에이전트 실행:

```
PDF 파일을 마크다운으로 변환하세요.

PDF 파일: $PDF_DIR/[파일명].pdf
마크다운 저장: $MD_DIR/[파일명].md

작업:
1. Read로 PDF 읽기
2. 마크다운 변환 (# 제목, ### 조항, **용어**, 표)
3. Write로 저장
4. python3 "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/scripts/extract_images.py" "[PDF경로]" -o "$IMG_DIR" -v
5. 완료 보고
```

### 3. 큐에서 제거

실행한 작업들을 큐에서 제거:
```bash
source "$CLAUDE_PLUGIN_DIR/skills/pdf-to-markdown/config.sh"
tail -n +$((COUNT+1)) "$QUEUE_FILE" > /tmp/pdf-queue-tmp.txt
mv /tmp/pdf-queue-tmp.txt "$QUEUE_FILE"
```

### 4. 상태 보고

- 실행한 파일 수
- 큐에 남은 파일 수

## 에이전트 완료 시

에이전트 완료 알림을 받으면 `/next-batch 1`로 다음 1개를 즉시 실행하여 항상 10개가 병렬 실행되도록 유지하세요.
