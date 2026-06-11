# OCI Always Free VM retry helper

Oracle Cloud Free Tier VM 생성을 백그라운드에서 반복 시도하는 도구입니다.

## 가장 쉬운 사용 순서

### 1. OCI CLI 로그인이 되는지 확인

PowerShell을 열고 아래 명령을 실행합니다.

```powershell
oci iam region list
```

지역 목록이 나오면 다음 단계로 가면 됩니다. 오류가 나오면 먼저 OCI CLI 설정이 필요합니다.

```powershell
oci setup config
```

### 2. 설정 파일 만들기

이 폴더에서 아래 명령을 실행합니다.

```powershell
Copy-Item .\oci-vm-config.example.json .\oci-vm-config.json
notepad .\oci-vm-config.json
```

메모장이 열리면 `replace-me` 부분을 본인 Oracle Cloud 값으로 바꿉니다.

반드시 바꿔야 하는 값:

- `compartmentId`
- `availabilityDomain`
- `subnetId`
- `imageId`
- `sshPublicKeyPath`

### 3. 백그라운드 반복 시작

```powershell
.\start-background-retry.cmd
```

이 명령을 실행하면 창을 닫아도 뒤에서 계속 시도합니다.

### 4. 상태 확인

```powershell
.\status-background-retry.cmd
```

마지막 시도 로그가 같이 표시됩니다. 성공하면 로그에 `Instance launch succeeded.`가 나옵니다.

### 5. 중지

```powershell
.\stop-background-retry.cmd
```

## 설정값 찾는 명령어

아래 명령은 값을 찾을 때만 필요합니다.

Availability Domain:

```powershell
oci iam availability-domain list --compartment-id <tenancy_or_compartment_ocid>
```

Subnet:

```powershell
oci network subnet list --compartment-id <compartment_ocid>
```

Image:

```powershell
oci compute image list --compartment-id <compartment_ocid> --shape VM.Standard.A1.Flex --operating-system "Oracle Linux" --sort-by TIMECREATED --sort-order DESC
```

## 참고

`oci-vm-config.json`에서 `maxAttempts`가 `0`이면 성공할 때까지 계속 시도합니다.

`retryDelaySeconds`는 한 번 실패한 뒤 다음 시도까지 기다리는 시간입니다. 너무 짧게 두면 API 요청이 과해질 수 있으니 45초 이상을 권장합니다.
