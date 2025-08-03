# === DTEDTRIS - Main Entry Point ===
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

# === OPTIMIZED MAIN GAME LOOP ===
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Show-SplashScreen
Clear-Host

# Performance monitoring variables for optimization feedback
$frameCount = 0
$lastFPSCheck = 0
$targetFrameTime = 16  # ~60 FPS target for smooth gameplay

do {
    $restart = $false

    # Initialize game components with performance optimizations enabled
    $script:app = [GameApp]::new($BOARD_WIDTH, $BOARD_HEIGHT, $TETROMINO_IDS, $GRAVITY_INTERVALS, $colors, $bgColors)
    $app.Renderer._PlayfieldFrameDrawn = $false
    $playerInput = [InputManager]::new($DAS_DELAY_MS, $DAS_INTERVAL_MS)
    $app.Engine.Spawn()

    $sw.Restart()
    $lastUpdateTime = 0
    $skipFrames = 0  # Frame skipping counter for performance under load

    while (-not $app.Game.GameOver) {
        $frameStart = $sw.ElapsedMilliseconds
        $dt = $frameStart - $lastUpdateTime
        $lastUpdateTime = $frameStart

        if (-not $app.Game.Paused) {
            # === Optimized input processing ===
            # Throttle input processing to reduce CPU overhead during rapid input
            $state = $null  # Initialize state variable for proper scoping
            
            if ($dt -ge 2) {  # Minimum 2ms between input processing cycles
                foreach ($act in $playerInput.GetActions()) {
                    switch ($act) {
                        'Left'      { 
                            if ($app.Engine.TryMove(-1,0,0)) { 
                                $app.NeedsDraw = $true 
                            }
                        }
                        'Right'     { 
                            if ($app.Engine.TryMove( 1,0,0)) { 
                                $app.NeedsDraw = $true 
                            }
                        }
                        'SoftDrop' {
                            # Soft drop provides immediate feedback for responsive gameplay feel
                            if ($app.Engine.TryMove(0, 1, 0)) {
                                $app.NeedsDraw = $true
                            } elseif ($app.Engine.IsGrounded()) {
                                $app.Engine.ForceLock()
                                $app.NeedsDraw = $true
                            }
                        }
                        'RotateCW'  { 
                            if ($app.Engine.TryRotateWithWallKick($app.Game.Active,1)) { 
                                $app.NeedsDraw = $true 
                            }
                        }
                        'HardDrop'  { 
                            HardDrop $app 
                        }
                        'Pause'     { $app.Game.Paused = $true; $app.NeedsDraw = $true }
                        'Quit'      { $app.Game.GameOver = $true }
                    }
                }
            }

            # === Optimized game state updates ===
            # Only update game logic when meaningful time has passed
            if ($dt -ge 1) {  # Minimum 1ms threshold for game updates
                $state = $app.Engine.Update($dt)
                if ($state) { $app.NeedsDraw = $true }
            }

            # === Intelligent frame skipping under system load ===
            # Skip rendering frames if system is struggling to maintain target FPS
            $frameTime = $sw.ElapsedMilliseconds - $frameStart
            if ($frameTime -gt $targetFrameTime * 2) {
                $skipFrames = [math]::Min($skipFrames + 1, 3)  # Skip up to 3 frames maximum
            } else {
                $skipFrames = [math]::Max($skipFrames - 1, 0)  # Reduce skipping when performance improves
            }

            # === Optimized rendering with frame skipping ===
            if ($app.NeedsDraw -and $skipFrames -eq 0) {
                # Ensure we have a valid state for rendering
                if (-not $state) { 
                    $state = $app.Engine.TakeSnapshot() 
                }
                
                # Only render when we have actual state changes to display
                if ($state) {
                    $app.Renderer.Draw($state, $app.Colors, $app.BackgroundColors, $app.Game.Ids)
                    $app.NeedsDraw = $false
                }
            }

        } else {
            # === Pause mode with minimal CPU usage ===
            $msg = '[ PAUSED ]'
            $msgLength = $msg.Length
            $centerX = [int](([Console]::WindowWidth  - $msgLength) / 2)
            $centerY = [int](([Console]::WindowHeight) / 2)

            Write-CursorPositionIfChanged $centerX $centerY
            [Console]::Write($msg)

            # Block efficiently until unpause key is pressed to save CPU during pause
            do {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'P') {
                    Write-CursorPositionIfChanged $centerX $centerY
                    [Console]::Write(' ' * $msgLength)
                    $app.Game.Paused = $false
                    $app.NeedsDraw = $true
                    $sw.Restart()  # Reset timing after pause to prevent time accumulation
                    $lastUpdateTime = 0
                    break
                }
            } while ($true)
        }

        # === Adaptive frame rate control for smooth gameplay ===
        $frameTime = $sw.ElapsedMilliseconds - $frameStart
        $sleepTime = [math]::Max(1, $targetFrameTime - $frameTime)
        
        # Dynamic sleep adjustment based on current system performance
        if ($frameTime -lt $targetFrameTime / 2) {
            # System is running fast - can afford slightly longer sleep for CPU efficiency
            $sleepTime = [math]::Min($sleepTime + 2, 10)
        } elseif ($frameTime -gt $targetFrameTime) {
            # System is struggling - reduce sleep time to maintain responsiveness
            $sleepTime = 1
        }

        # === Performance monitoring and cache management ===
        $frameCount++
        if ($frameStart - $lastFPSCheck -gt 1000) {
            # Performance logging every second for optimization feedback
            # Uncomment for debugging: Write-Host "FPS: $($frameCount), Frame time: $($frameTime)ms" -ForegroundColor DarkGray
            $frameCount = 0
            $lastFPSCheck = $frameStart
            
            # Periodic cache optimization to prevent memory bloat during extended play
            if ($app.Renderer -and $app.Renderer.GetRenderingStats) {
                $renderStats = $app.Renderer.GetRenderingStats()
                # Renderer automatically manages its own cache cleanup
            }
            
            if ($app.Engine -and $app.Engine.GetEngineStats) {
                $engineStats = $app.Engine.GetEngineStats()
                # Clear collision cache if it grows too large
                if ($engineStats.CollisionCacheSize -gt 500) {
                    $app.Engine.ClearPerformanceCaches()
                }
            }
        }

        # === Efficient idle handling ===
        # Only sleep if no input is pending and no immediate updates are needed
        if (-not [Console]::KeyAvailable -and -not $app.NeedsDraw -and $sleepTime -gt 0) {
            Start-Sleep -Milliseconds $sleepTime
        }
    }

    # === Game Over Screen with efficient input handling ===
    Show-GameOverScreen

    # Block efficiently during game over screen to minimize CPU usage
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
        # Small sleep to prevent busy waiting during game over screen
        Start-Sleep -Milliseconds 10
    } while ($true)

    Clear-GameOverScreen

} while ($restart)
