# Getting GolfDB

**GolfDB** = 1,400 trimmed golf-swing videos, each labeled with 8 event frames +
club / view / player metadata. Paper: arXiv 1903.06528. Code + data:
`https://github.com/wmcnally/GolfDB`.

## What to download
1. **Annotations** — `golfDB.pkl` (or `.mat`) from the repo: one row per clip with
   the 8 event frame indices, bbox, club, view (`face-on` / `down-the-line`),
   player, and the train/val **split** columns (splits 1–4 for cross-val; split 1
   is the common default).
2. **Preprocessed clips** — the repo hosts **160×160 pre-cropped videos** (download
   link in the repo README). This is the fast path — no YouTube scraping.
   - *Alternative:* the annotations include YouTube URLs; you can download the raw
     videos and crop them yourself with the repo's preprocessing.

## Layout expected by this project
```
data/
  golfDB.pkl            # annotations + splits
  videos/               # 160x160 clips (gitignored — large)
  poses/                # our extracted pose sequences (gitignored)
```

## Then
- `python -m swing.pose` extracts per-frame pose (MediaPipe) → `data/poses/` as
  keypoint sequences (one array per clip). That's the model's actual input — so the
  bulky videos aren't needed at train time once poses are cached.
- Train/val use GolfDB's split columns (report on split 1; optionally cross-val).

## Licensing
GolfDB clips are sourced from public YouTube uploads for research; use for the
course project + cite the paper. Keep `videos/` and `poses/` out of git (already in
`.gitignore`).
