# 어디소 (whereis)

물건 보관 위치를 등록하고 찾는 Flutter 앱.

## 기능

- 물품 등록/수정/삭제 (사진, 수량, 유효기한, 비고, 분류, 층·장소)
- 조건 검색 (층 → 장소 → 분류 선택 + 품목 키워드 자동완성)
- 엑셀 내보내기 / 가져오기 — **가져오기는 기존 물품을 모두 삭제하고 엑셀
  내용으로 교체**한다 (진행 전 확인 대화상자 표시)
- 선택 모드 일괄수정/일괄삭제
- sqflite 로컬 DB, 드롭다운 항목(층·장소·분류·품목) 자동 관리

## 개발 환경

- Flutter 3.29.x stable (Dart ^3.7.2), 권장 설치 경로 `C:\tools\flutter`
- Android Studio / Android SDK (빌드 시)

## 테스트

```bat
flutter analyze
run_tests.bat
```

### Windows 사용자명에 한글이 있을 때

사용자명이 한글이면(예: `C:\Users\쑤`) TEMP 경로에 비ASCII 문자가 섞여
`flutter test` 로드 단계에서 flutter_tester가 크래시한다
(`Connection closed before test suite loaded`). 루트의 `run_tests.bat`이
ASCII 경로를 TEMP로 지정해 우회한다. 직접 실행하려면:

```bat
set TEMP=C:\.whereis_test_tmp
set TMP=C:\.whereis_test_tmp
flutter test
```

### 골든 이미지 테스트

위젯 테스트는 화면 골든 이미지(`test/goldens/`)와 픽셀을 비교하며,
Windows 시스템 폰트(Malgun Gothic)를 사용해 렌더링한다. UI를 변경해
골든을 다시 생성해야 할 때는:

```bat
run_tests.bat --update-goldens
```

날짜 선택 화면의 골든(`03_date_picker.png`)은 달력을 항상 고정된 달
(2020년 1월)로 이동시킨 뒤 촬영하므로 실행 시점과 무관하게 안정하다.

## 배포 (APK)

- GitHub Releases에 APK를 첨부해 배포한다 (디버그 빌드는 prerelease로 표시).
- **APK 파일명은 항상 `ndokhak_udiso_`로 시작한다.**
  - 디버그: `ndokhak_udiso_debug_<yyyyMMdd>.apk` (릴리스 태그: `debug-<yyyyMMdd>`)
  - 릴리스: `ndokhak_udiso_release_<버전>.apk`
- 빌드 방법: `flutter build apk --debug` / `flutter build apk --release`

