# 어디소 (whereis)

물건 보관 위치를 등록하고 찾는 Flutter 앱.

## 기능

- 물품 등록/수정/삭제 (사진, 수량, 유효기한, 비고, 분류, 층·장소)
- 등록/수정 화면에 **사진 저장경로 및 파일명**을 항상 표시한다 (사진이 없으면
  `등록된 사진 없음`)
- 필수 입력값은 **품목과 장소1** 두 개만 검사한다 (나머지는 선택)
- 조건 검색 (층 → 장소 → 분류 선택 + 품목 키워드 자동완성)
- 엑셀 내보내기 / 가져오기 — **가져오기는 기존 물품을 모두 삭제하고 엑셀
  내용으로 교체**한다 (진행 전 확인 대화상자 표시)
  - 가져오기 결과에 **가져온 파일의 파일명과 경로**를 표시하고, 품목 또는
    장소1이 비어 있는 행은 제외한다
  - 엑셀에 `사진경로` 값이 있고 그 파일이 기기에 실제로 있으면 사진을 연결하고,
    없으면 `사진파일명`으로 앱 사진 폴더에서 찾아 연결한다. 둘 다 없으면
    사진 없이 등록한다 (건수는 결과에 표시)
- **사진 백업/복원** — 사진 전체를 zip 하나로 내보내고 다시 가져온다
  (사진은 앱 내부에만 있어서 앱을 지우면 사라지므로, PC 등에 보관했다가
  복원하면 엑셀의 `사진경로`와 다시 연결된다)
- 선택 모드 일괄수정/일괄삭제
- sqflite 로컬 DB, 드롭다운 항목(층·장소·분류·품목) 자동 관리

### 엑셀 파일 저장/선택 위치

양식 받기/내보내기는 기본적으로 스마트폰에서 바로 볼 수 있는 **다운로드**
폴더에 저장하고, 저장된 **파일명과 실제 경로**를 스낵바로 알려 준다.
스낵바의 **`다른 폴더`** 버튼을 누르면 시스템 저장 대화상자가 열려 원하는
위치를 고를 수 있다 (기본 위치는 다운로드). 파일명은 `ndokhak_udiso_`로
시작한다.

- 양식: `ndokhak_udiso_template.xlsx`
- 내보내기: `ndokhak_udiso_<yyyyMMdd_HHmmss>.xlsx`
- 엑셀 열: 품목, 분류, 수량, 유효기한, 비고, 층, 장소1, 장소2, 장소3,
  **사진경로, 사진파일명**
- 기본 저장 폴더(Android): `/storage/emulated/0/Download`
  - Android 10 이상은 MediaStore를 사용하므로 저장소 권한이 필요 없다.
  - Android 10 미만이거나 저장에 실패하면 시스템 저장 대화상자(SAF)로
    대체하며, 이때 경로는 문서 URI로 표시된다.
- 엑셀 가져오기 파일 선택 창도 **다운로드** 폴더에서 시작한다.
- 사진 백업: `ndokhak_udiso_photos_<yyyyMMdd_HHmmss>.zip` (다운로드 폴더)
  - 백업 파일 안에는 사진 파일들이 원래 파일명 그대로 들어 있다.
  - **복원 순서**: `사진 파일 가져오기(복원)` → `엑셀 파일 가져오기`.
    이 순서로 해야 엑셀의 사진 정보가 복원된 사진과 연결된다.

### 사진 백업/복원

앱 상단의 **일괄등록 · 백업** 버튼(업로드 아이콘)을 누르면 다음을 고를 수 있다.

- 엑셀 양식 파일 받기 / 엑셀 파일 가져오기
- **사진 파일 내보내기 (백업)** — 앱에 저장된 사진 전체를 zip으로 내보낸다
  (내보낼 사진이 없으면 안내 메시지를 보여 준다)
- **사진 파일 가져오기 (복원)** — 백업 zip을 골라 사진 폴더에 되돌린다

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

