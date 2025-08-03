# DTEDTRIS - Usage Guide

A colorful, fully‑featured Tetris clone written **entirely in PowerShell** with a modular architecture.

## 🚀 Quick Start

### Prerequisites
- **Windows PowerShell 5.1** or **PowerShell 7+** (cross-platform)
- ANSI-capable terminal (Windows Terminal, ConEmu, iTerm2, VS Code terminal, etc.)
- Console window of at least **80×30** characters

### Installation & Running
```powershell
# 1. Navigate to the game directory
cd Dtedtris

# 2. Run the game (bypass execution policy if needed)
pwsh -ExecutionPolicy Bypass -File .\Dtedtris.ps1

# On Windows PowerShell 5.1, use:
# powershell -ExecutionPolicy Bypass -File .\Dtedtris.ps1
```

## 📁 File Structure

```
Dtedtris/
├── Dtedtris.ps1              # 🎮 Main entry point - START HERE
├── Config/
│   └── GameConfig.ps1        # ⚙️  Game settings and constants
├── Core/                     # 🎯 Game logic and mechanics
│   ├── Point.ps1             #    Point class and utilities
│   ├── TetrominoData.ps1     #    Piece shapes and kick tables
│   ├── InputManager.ps1      #    Keyboard input with DAS
│   ├── Tetromino.ps1         #    Tetromino piece class
│   ├── BitBoard.ps1          #    Game board collision detection
│   ├── GameContext.ps1       #    Game state management
│   ├── GameEngine.ps1        #    Core game mechanics
│   └── GameApp.ps1           #    Application wrapper
└── UI/                       # 🎨 User interface and rendering
    ├── Panel.ps1             #    Base panel framework
    ├── Panels.ps1            #    Score, stats, next piece panels
    ├── ConsoleRenderer.ps1   #    ANSI color rendering engine
    └── UIHelpers.ps1         #    Splash screen and utilities
```

## ⌨️ Game Controls

| Key | Action |
|-----|--------|
| **← / →** | Move piece left/right |
| **↓** | Soft drop (faster fall) |
| **↑** | Rotate clockwise |
| **Space** | Hard drop (instant lock) |
| **P** | Pause/resume |
| **Esc** | Quit to game over screen |
| **R** (game over) | Restart |
| **Q** (game over) | Quit application |

## 🎛️ Customization

### Quick Tweaks
Edit **`Config/GameConfig.ps1`** to modify:

**Colors** - Change piece colors:
```powershell
$script:colors = @{
    I = @(255, 179, 71)   # Orange I-piece
    O = @(255, 213, 102)  # Yellow O-piece
    # ... modify RGB values
}
```

**Game Speed** - Adjust gravity intervals:
```powershell
$script:GRAVITY_INTERVALS = @(800,717,633,...)  # milliseconds per drop
```

**Controls** - Modify **`Core/InputManager.ps1`**:
```powershell
# Change key mappings
'LeftArrow'  { $actions += [PlayerAction]::Left }
'RightArrow' { $actions += [PlayerAction]::Right }
```

**Board Size** - Edit dimensions:
```powershell
$script:BOARD_WIDTH  = 10    # Standard width
$script:BOARD_HEIGHT = 22    # Standard height
```

### Advanced Customization

| Component | File | What You Can Change |
|-----------|------|---------------------|
| **Piece Shapes** | `Core/TetrominoData.ps1` | Add new pieces, modify rotations |
| **Wall Kicks** | `Core/TetrominoData.ps1` | SRS kick tables for rotation |
| **Scoring** | `Config/GameConfig.ps1` | Line clear point values |
| **UI Layout** | `UI/ConsoleRenderer.ps1` | Panel positions and sizes |
| **Input Timing** | `Config/GameConfig.ps1` | DAS delay/repeat rates |

## 🔧 Troubleshooting

### Common Issues

**"Execution Policy" Error**
```powershell
# Use bypass flag
pwsh -ExecutionPolicy Bypass -File .\Dtedtris.ps1
```

**Console Too Small**
- Resize terminal to at least 80×30 characters
- The game will display current size and requirements

**Colors Not Showing**
- Ensure you're using an ANSI-capable terminal
- Try Windows Terminal, VS Code terminal, or ConEmu

**Game Runs Slowly**
- Close other applications
- Try reducing `RENDER_CELL_WIDTH` in config

### Performance Tips
- Use **Windows Terminal** for best performance
- Ensure console buffer size matches window size
- Close unnecessary background applications

## 🎮 Game Features

### Authentic NES Gameplay
- **10×22 playfield** with proper spawn offset
- **7-bit LFSR RNG** matching NES Tetris randomization
- **Gravity curve** from 800ms to 17ms across 29 levels
- **Standard scoring**: 40/100/300/1200 points × (level + 1)

### Modern Quality-of-Life
- **Ghost piece** shows where piece will land
- **Next piece preview** in dedicated panel
- **Piece statistics** with counts and mini-previews
- **Wall kicks** using Super Rotation System (SRS)
- **Lock delay** with movement/rotation resets
- **DAS/ARR** for smooth piece movement

### Visual Features
- **24-bit RGB colors** for each tetromino type
- **Unicode box-drawing** for crisp panel borders
- **Dirty-row rendering** for optimal performance
- **Line clear animations** with flashing effects

## 📊 Game Mechanics

| Setting | Value | Description |
|---------|-------|-------------|
| **Board Size** | 10×22 | Standard Tetris dimensions |
| **Spawn Offset** | Y = -2 | Pieces spawn above visible area |
| **Lines per Level** | 10 | Level increases every 10 lines |
| **Lock Delay** | 500ms | Time before piece locks when grounded |
| **Lock Resets** | 2 maximum | Movement/rotation can delay locking |
| **DAS Delay** | 200ms | Initial delay before auto-repeat |
| **DAS Interval** | 50ms | Auto-repeat rate for held keys |

## 🛠️ Development

### Adding New Features
1. **New Panel Type**: Extend `Panel` class in `UI/Panels.ps1`
2. **Input Commands**: Add to `PlayerAction` enum and `InputManager`
3. **Game Modes**: Modify `GameEngine` or create new engine classes
4. **Visual Effects**: Extend `ConsoleRenderer` methods

### File Dependencies
Import order matters due to dependencies:
1. **Config** (defines constants)
2. **Point** (used by other classes)
3. **TetrominoData** (referenced by engine/renderer)
4. **Core classes** (in dependency order)
5. **UI classes** (depend on core)

### Testing Individual Components
```powershell
# Test specific module
. .\Config\GameConfig.ps1
. .\Core\Point.ps1
# ... test Point class functionality
```

## 📝 License

MIT License - see original repository for details.

## 🎯 Credits

- **Original Game**: Alexey Pajitnov (Tetris, 1984)
- **NES Research**: Tetris community documentation
- **PowerShell Implementation**: DTEDTRIS project

---

**Enjoy the game!** 🎮 Feel free to customize, extend, and share your modifications.