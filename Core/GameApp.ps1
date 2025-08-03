# === GAME APPLICATION ===

class GameApp {
    [GameContext]     $Game
    [GameEngine]      $Engine
    [ConsoleRenderer] $Renderer
    [bool]            $NeedsDraw = $true

    [hashtable] $Colors
    [hashtable] $BackgroundColors

    GameApp([int]$w, [int]$h, [string[]]$ids, [int[]]$gInt, [hashtable]$colors, [hashtable]$bgColors) {
        $this.Colors = $colors
        $this.BackgroundColors = $bgColors
        
        $this.Game = [GameContext]::new($w, $h, $ids, $gInt)
        $this.Engine = [GameEngine]::new($this.Game)
        $this.Renderer = [ConsoleRenderer]::new($w, $h, $colors)
    }
}

# === HELPER FUNCTIONS ===

function HardDrop($app) {
    # Calculate drop distance using cached ghost piece
    $ghost = $app.Engine.GetGhostCached()
    if ($ghost) {
        $app.Game.Active.Y = $ghost.Y
        $app.Engine.ForceLock()
    }
    $app.NeedsDraw = $true
}