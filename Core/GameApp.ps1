# === GAME APPLICATION ===

. "$PSScriptRoot\GameContext.ps1"

class GameApp {
    [GameContext]     $Game
    [GameEngine]      $Engine
    [ConsoleRenderer] $Renderer
    [GameConfig]      $Config
    [bool]            $NeedsDraw = $true

    # Backward compatibility properties
    [hashtable] $Colors
    [hashtable] $BackgroundColors

    # Constructor that matches original signature for backward compatibility
    GameApp([int]$w, [int]$h, [string[]]$ids, [int[]]$gInt, [hashtable]$colors, [hashtable]$bgColors) {
        # Create config from parameters
        $this.Config = $Global:GameConfig
        $this.Config.BOARD_WIDTH = $w
        $this.Config.BOARD_HEIGHT = $h
        $this.Config.TETROMINO_IDS = $ids
        $this.Config.GRAVITY_INTERVALS = $gInt
        $this.Config.Colors = $colors
        $this.Config.BackgroundColors = $bgColors
        
        # Set backward compatibility properties
        $this.Colors = $colors
        $this.BackgroundColors = $bgColors
        
        $this.InitializeGameSystems()
    }
    
    # Alternative constructor that takes config object
    GameApp([GameConfig]$config) {
        $this.Config = $config
        $this.Colors = $config.Colors
        $this.BackgroundColors = $config.BackgroundColors
        $this.InitializeGameSystems()
    }

    [void] InitializeGameSystems() {
        # Create game context with configuration
        $this.Game = [GameContext]::new(
            $this.Config.BOARD_WIDTH,
            $this.Config.BOARD_HEIGHT,
            $this.Config.TETROMINO_IDS,
            $this.Config.GRAVITY_INTERVALS
        )

        # Create engine - use backward compatible constructor for now
        $this.Engine = [GameEngine]::new($this.Game)

        # Create renderer with color configuration
        $this.Renderer = [ConsoleRenderer]::new(
            $this.Config.BOARD_WIDTH,
            $this.Config.BOARD_HEIGHT,
            $this.Config.Colors
        )
    }

    [void] ResetGame() {
        # Reinitialize all game systems for a fresh start
        $this.InitializeGameSystems()
        $this.NeedsDraw = $true
    }

    [GameState] GetCurrentState() {
        return $this.Engine.TakeSnapshot()
    }

    [void] RequestRedraw() {
        $this.NeedsDraw = $true
    }

    [bool] ShouldRedraw() {
        return $this.NeedsDraw
    }

    [void] MarkDrawComplete() {
        $this.NeedsDraw = $false
    }
}

# === PLAYER ACTION HANDLERS ===

class PlayerActionHandler {
    [GameApp] $App

    PlayerActionHandler([GameApp]$app) {
        $this.App = $app
    }

    [bool] HandleAction([PlayerAction]$action) {
        # Returns true if the action caused a state change
        $result = $false
        
        switch ($action) {
            'Left'      { $result = $this.App.Engine.TryMove(-1, 0, 0) }
            'Right'     { $result = $this.App.Engine.TryMove(1, 0, 0) }
            'SoftDrop'  { $result = $this.HandleSoftDrop() }
            'RotateCW'  { $result = $this.App.Engine.TryRotateWithWallKick($this.App.Game.Active, 1) }
            'HardDrop'  { $this.HandleHardDrop(); $result = $true }
            'Pause'     { $this.App.Game.Paused = $true; $result = $true }
            'Quit'      { $this.App.Game.GameOver = $true; $result = $true }
            default     { $result = $false }
        }
        
        return $result
    }

    [bool] HandleSoftDrop() {
        # Soft drop tries to move down, or locks if grounded
        if ($this.App.Engine.TryMove(0, 1, 0)) {
            return $true
        } elseif ($this.App.Engine.IsGrounded()) {
            $this.App.Engine.ForceLock()
            return $true
        }
        return $false
    }

    [void] HandleHardDrop() {
        # Calculate drop distance using cached ghost piece
        $ghost = $this.App.Engine.GetGhostCached()
        if ($ghost) {
            $this.App.Game.Active.Y = $ghost.Y
            $this.App.Engine.ForceLock()
        }
    }
}

# === LEGACY COMPATIBILITY FUNCTIONS ===

function HardDrop($app) {
    # Maintain backward compatibility with existing code
    $handler = [PlayerActionHandler]::new($app)
    $handler.HandleHardDrop()
    $app.NeedsDraw = $true
}