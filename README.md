# DTEDTRIS
*A colorful, fully‑featured Tetris clone written **entirely in PowerShell***

---

## ✨ What makes DTEDTRIS special?

### Zero‑friction setup  
* Pure script – no modules, no DLLs, no installer.  
* Runs on **Windows PowerShell 5.1** _or_ **cross‑platform PowerShell 7+**.  
* Any ANSI‑capable console works: Windows Terminal, ConEmu, iTerm2, VS Code, etc.

### True‑color, Unicode UI  
* 24‑bit foreground/background colours for each cell.  
* Box‑drawing characters for crisp panel borders.  
* Variable `RENDER_CELL_WIDTH` lets you scale the board horizontally.

### Authentic NES gameplay core  
* **Playfield:** classic 10 × 22 well with spawn offset –2.  
* **7‑bit LFSR RNG** plus “retry if repeat” rule – mirrors the 1989 NES behaviour.  
* Gravity curve matches levels 0‑28 of the original: 800 ms down to 17 ms per row.  
* Standard 40‑100‑300‑1200 line‑clear scoring.

### Quality‑of‑life niceties (fully configurable)

| Feature | Default behaviour | Where to tune |
|---------|-------------------|---------------|
| **Ghost piece** | Always visible; updates in real‑time as you move/rotate. | `Get-GhostPieceFrom`, enable/disable or recolour `CHAR_GHOST`. |
| **Next‑queue preview** | Single upcoming piece drawn in its own framed panel. | Panel sizing near the top of script. |
| **Piece statistics** | Counts of each tetromino rendered with mini glyphs + totals. | `StatsPanel` class. |
| **Soft drop** | Auto‑repeats every 50 ms (ignores DAS delay). | `$DAS_INTERVAL_MS` in settings. |
| **Hard drop** | Spacebar instantly locks piece & awards drop score. | `HardDrop` helper. |
| **Wall kicks** | Super‑Rotation‑System (SRS) tables with separate data for **I** piece. | `$TetrominoKicks` hash. |
| **DAS / ARR** | 200 ms delay, 50 ms repeat – affects ← and →. | `$DAS_DELAY_MS`, `$DAS_INTERVAL_MS`. |
| **Lock delay** | 500 ms, up to 2 resets through movement/rotation. | `$LOCK_DELAY_MS`, `$LOCK_RESET_LIMIT`. |
| **Pause / Resume** | Press **P** to freeze the game; any logic timers are halted. | Handled in main loop. |
| **Instant restart** | On Game‑Over press **R**; engine & UI re‑initialise in < 5 ms. | Main loop outer shell. |
| **Dirty‑row rendering** | Only the rows & panels that changed are redrawn each frame. | `ConsoleRenderer` caches. |

### Performance‑minded implementation  
* Pre‑expanded bit‑masks for collision checks – no per‑frame shape math.  
* Dirty‑line caches, per‑row `StringBuilder`s, and cursor‑state tracking minimise console writes.  
* Gravity, DAS, lock‑delay all driven by a single high‑resolution stopwatch.

### Hackable by design  
Every constant lives in the “**SCRIPT SETTINGS**” block. Change numbers, colours, even the gravity curve – nothing else to touch.

---

## 📷 Quick look  
*(screenshot coming soon)*

---

## ⌨️ Controls

| Key                  | Action                    |
| -------------------- | ------------------------- |
| **← / →**            | Move piece left / right   |
| **↓**                | Soft drop                 |
| **↑**                | Rotate clockwise          |
| **Space**            | Hard drop (instant lock)  |
| **P**                | Pause / resume            |
| **Esc**              | Quit to Game‑Over screen  |
| **R** (on Game‑Over) | Restart                   |
| **Q** (on Game‑Over) | Quit application          |

---

## 🚀 Getting started

1. **Clone or download** this repository.  
2. Open an **ANSI‑capable** terminal.  
3. Run:

```powershell
# One‑off run (bypass ExecutionPolicy only for this session)
pwsh -ExecutionPolicy Bypass -File .\dtedtris.ps1
```

> On Windows PowerShell 5.1 substitute `powershell` for `pwsh`.

---

## 📐 Game mechanics at a glance

| Setting                     | Value / Behaviour                     |
| --------------------------- | ------------------------------------- |
| Playfield size              | 10 × 22 (spawn Y offset –2)           |
| Lines per level             | 10                                    |
| Gravity intervals (ms)      | 800 → 17 (29 levels)                  |
| DAS delay / interval        | 200 ms / 50 ms                        |
| Lock‑delay / resets         | 500 ms, 2 resets                      |
| Line‑clear scores           | 0, 40, 100, 300, 1200 × (level + 1)    |
| Randomiser                  | NES 7‑bit LFSR with retry             |
| Wall‑kicks                  | SRS (I vs others)                     |

---

## 🎨 Customisation

All tunables sit in the *“SCRIPT SETTINGS”* block near the top of `dtedtris.ps1`.  
Change a constant, hit **R** to restart, and your tweak is live.

---

## 🛠️ Architecture overview

* **InputManager** – debounced keystrokes, DAS repeat logic.  
* **Tetromino / BitBoard** – geometry, collision masks, bit‑board storage.  
* **GameEngine** – gravity, lock‑delay, line‑clears, scoring, RNG, wall‑kicks.  
* **ConsoleRenderer** – dirty‑row rendering, ANSI colour cache, UI panels.  
* **GameApp (main loop)** – spawns engine, renderer, handles pause/resume and restarts.  

---

## ⚖️ License

MIT – see `LICENSE` for details. Enjoy, fork, and share!

---

## 🙏 Credits & inspiration

* **Alexey Pajitnov** – original Tetris (1984).  
* Study of *Famicom/NES* RNG & speed tables by the Tetris community.  
* PowerShell ANSI trickery from assorted blog posts and GitHub gists.

*(Have fun! Feel free to open issues or PRs – contributions welcome.)*