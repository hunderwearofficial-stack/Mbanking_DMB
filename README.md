# Mobile Banking Bank DMB

Repository aplikasi Mobile Banking PT Bank Perekonomian Rakyat Dana Mandiri Bogor.

## Alur Branch

feature/nama-fitur -> develop -> staging -> main

| Branch | Lingkungan | Siapa yang menggabungkan (merge) |
|---|---|---|
| develop | Development | Developer, melalui Merge Request |
| staging | Staging / UAT | Lead developer / Tim IT, setelah code review |
| main | Production | Pejabat berwenang, setelah UAT disetujui |

## Aturan

- Tidak ada push langsung ke develop, staging, dan main. Semua perubahan wajib melalui Merge Request.
- Setiap fitur dikerjakan di branch feature/nama-fitur yang dibuat dari develop.
- Dilarang menyimpan password, API key, atau data nasabah di repository.
