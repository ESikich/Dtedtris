Write-Host "Starting game# === DTEDTRIS - Main Entry Point ==="
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Get the script directory
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Import all modules in dependency order
try {
    Write-Host "Loading DTEDTRIS..." -ForegroundColor Green
    
    . "$ScriptRoot\Config\GameConfig.ps1"
    Write-Host "  Config" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\Point.ps1"
    Write-Host "  Point class" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\TetrominoData.ps1"
    Write-Host "  Tetromino data" -ForegroundColor Gray
    
    . "$ScriptRoot\UI\Panel.ps1"
    Write-Host "  Panel framework" -ForegroundColor Gray
    
    . "$ScriptRoot\UI\Panels.ps1"
    Write-Host "  UI panels" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\InputManager.ps1"
    Write-Host "  Input manager" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\Tetromino.ps1"
    Write-Host "  Tetromino class" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\BitBoard.ps1"
    Write-Host "  Game board" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\GameContext.ps1"
    Write-Host "  Game context" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\GameEngine.ps1"
    Write-Host "  Game engine" -ForegroundColor Gray
    
    . "$ScriptRoot\UI\ConsoleRenderer.ps1"
    Write-Host "  Renderer" -ForegroundColor Gray
    
    . "$ScriptRoot\Core\GameApp.ps1"
    Write-Host "  Game app" -ForegroundColor Gray
    
    . "$ScriptRoot\UI\UIHelpers.ps1"
    Write-Host "  UI helpers" -ForegroundColor Gray
    
    Write-Host "Ready!" -ForegroundColor Green
} catch {
    Write-Host "Error loading modules: $_" -ForegroundColor Red
    Write-Host "Make sure all files are in the correct directory structure." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# === CONSOLE SETUP ===
$WINDOW_TITLE = 'Dtedtris'
[Console]::Title = $WINDOW_TITLE
[Console]::Clear()
[Console]::CursorVisible = $false

# === WINDOW SIZE CHECK ===
$requiredWidth = 80
$requiredHeight = 30

function Show-ResizePrompt {
    [Console]::Clear()
    $currentWidth  = [Console]::WindowWidth
    $currentHeight = [Console]::WindowHeight
    $msg1 = "Console must be at least ${requiredWidth} x ${requiredHeight}."
    $msg2 = "Current size: ${currentWidth} x ${currentHeight}"
    $msg3 = "Resize the window and press Enter when ready..."

    $x1 = [math]::Floor(([Console]::WindowWidth - $msg1.Length) / 2)
    $x2 = [math]::Floor(([Console]::WindowWidth - $msg2.Length) / 2)
    $x3 = [math]::Floor(([Console]::WindowWidth - $msg3.Length) / 2)
    $y  = [math]::Floor([Console]::WindowHeight / 2)

    [Console]::SetCursorPosition($x1, $y)
    [Console]::WriteLine($msg1)
    [Console]::SetCursorPosition($x2, $y + 1)
    [Console]::WriteLine($msg2)
    [Console]::SetCursorPosition($x3, $y + 3)
    [Console]::WriteLine($msg3)
}

while (
    [Console]::WindowWidth -lt $requiredWidth -or 
    [Console]::WindowHeight -lt $requiredHeight
) {
    Show-ResizePrompt
    Start-Sleep -Milliseconds 200
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter' -and 
            [Console]::WindowWidth -ge $requiredWidth -and 
            [Console]::WindowHeight -ge $requiredHeight) {
            break
        }
    }
}
[Console]::Clear()

# === MAIN GAME LOOP ===
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Show-SplashScreen
Clear-Host

do {
    $restart = $false

    $script:app = [GameApp]::new($BOARD_WIDTH, $BOARD_HEIGHT, $TETROMINO_IDS, $GRAVITY_INTERVALS, $colors, $bgColors)
    $app.Renderer._PlayfieldFrameDrawn = $false
    $playerInput = [InputManager]::new($DAS_DELAY_MS, $DAS_INTERVAL_MS)
    $app.Engine.Spawn()

    $sw.Restart()

    while (-not $app.Game.GameOver) {
        $dt = $sw.ElapsedMilliseconds
        $sw.Restart()

        if (-not $app.Game.Paused) {
            # === Handle input ===
            foreach ($act in $playerInput.GetActions()) {
                switch ($act) {
                    'Left'      { if ($app.Engine.TryMove(-1,0,0)) { $app.NeedsDraw = $true } }
                    'Right'     { if ($app.Engine.TryMove( 1,0,0)) { $app.NeedsDraw = $true } }
                    'SoftDrop' {
                        if ($app.Engine.TryMove(0, 1, 0)) {
                            $app.NeedsDraw = $true
                        } elseif ($app.Engine.IsGrounded()) {
                            $app.Engine.ForceLock()
                            $app.NeedsDraw = $true
                        }
                    }
                    'RotateCW'  { if ($app.Engine.TryRotateWithWallKick($app.Game.Active,1)) { $app.NeedsDraw = $true } }
                    'HardDrop'  { HardDrop $app }
                    'Pause'     { $app.Game.Paused = $true; $app.NeedsDraw = $true }
                    'Quit'      { $app.Game.GameOver = $true }
                }
            }

            # === Apply gravity, etc. ===
            $state = $app.Engine.Update($dt)
            if ($state) { $app.NeedsDraw = $true }

            # === Redraw if needed ===
            if ($app.NeedsDraw) {
                if (-not $state) { $state = $app.Engine.TakeSnapshot() }
                $app.Renderer.Draw($state, $app.Colors, $app.BackgroundColors, $app.Game.Ids)
                $app.NeedsDraw = $false
            }
        } else {
            # === Pause mode ===
            $msg = '[ PAUSED ]'
            $msgLength = $msg.Length
            $centerX = [int](([Console]::WindowWidth  - $msgLength) / 2)
            $centerY = [int](([Console]::WindowHeight) / 2)

            Write-CursorPositionIfChanged $centerX $centerY
            [Console]::Write($msg)

            do {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'P') {
                    Write-CursorPositionIfChanged $centerX $centerY
                    [Console]::Write(' ' * $msgLength)
                    $app.Game.Paused = $false
                    $app.NeedsDraw = $true
                    $sw.Restart()
                    break
                }
            } while ($true)
        }

        # === Idle sleep if nothing to do ===
        if (-not [Console]::KeyAvailable -and -not $app.NeedsDraw) {
            Start-Sleep -Milliseconds 1
        }
    }

    Show-GameOverScreen

    do {
        $key = [Console]::ReadKey($true)
        $ch = [char]::ToUpper($key.KeyChar)
        if ($ch -eq 'R') {
            $restart = $true
            break
        } elseif ($ch -eq 'Q' -or $ch -eq 'C') {
            $restart = $false
            break
        }
    } while ($true)

    Clear-GameOverScreen

} while ($restart)