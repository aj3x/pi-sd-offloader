# File Structures

## Synology
Photos
├── Sony A7C
│   ├── 20240101
│   │   ├── CLIP
|   |   |   └── C0215.MP4
│   │   └── DCIM
|   |       └── A7C01610.ARW
│   └── 20250304
├── Insta360 Go3
└── DJI

## Cameras
I want all files from the DCIM. These should be separated by their camera type. In almost all cases, the entire SD card has only been used by one computer.
A7C also includes videos under the folder `PRIVATE/M4ROOT/CLIP`

### A7C
```
.
├── AVF_INFO
│   ├── AVIN0001.BNP
│   ├── AVIN0001.INP
│   ├── AVIN0001.INT
│   └── PRV00001.BIN
├── DCIM
│   └── 100MSDCF
│       ├── A7C01610.ARW
│       ├── A7C01611.ARW
│       ├── A7C01612.ARW
│       ├── A7C01612.JPG
│       └── A7C01613.JPG
└── PRIVATE
    └── M4ROOT
        ├── CLIP
        │   ├── C0215M01.XML
        │   └── C0215.MP4
        ├── GENERAL
        ├── MEDIAPRO.XML
        ├── STATUS.BIN
        ├── SUB
        └── THMBNL
            └── C0215T01.JPG
```

### Fujifilm FP XP150
```
.
├── DCIM
│   └── 100_FUJI
│       ├── DSCF0001.JPG
│       └── DSCF0013.MOV
└── FGPS
    └── FGPS0001.LOG
```

### DJI Osmo Pocket 3
```
.
├── DCIM
│   └── DJI_001
│       ├── DJI_20250509045707_0001_D.LRF
│       ├── DJI_20250509045707_0001_D.MP4
│       └── DJI_20250509045707_0001_D.WAV
└── MISC
    └── M4ROOT
        ├── IDX
        ├── THM
        │   └── DJI_001
        │       ├── DJI_20250509045707_0001_D.SCR
        │       └── DJI_20250509045707_0001_D.THM
        └── PP-101.db
```