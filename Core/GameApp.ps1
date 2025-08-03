# === GAME APPLICATION ===

class GameApp {
    [GameContext]     $Game
    [GameEngine]      $Engine
    [ConsoleRenderer] $Renderer
    [bool]            $NeedsDraw = $true

    [hashtable] $Colors
    [hashtable] $BackgroundColors

    GameApp([int]$w,[int]$h,[string[]]$ids,[int[]]$gInt,
            [hashtable]$colors,[hashtable]$bgColors) {

        $this.Game      = [GameContext]::new($w,$h,$ids,$gInt)
        $this.Engine    = [GameEngine]::new($this.Game)
        $this.Renderer  = [ConsoleRenderer]::new($w,$h,$colors)
        $this.Colors    = $colors
        $this.BackgroundColors = $bgColors
    }
}

# === HELPER FUNCTIONS ===

function HardDrop($app) {
    # Use the same fast distance calc as ghost
    $ghost = Get-GhostPieceFrom -board $app.Game.Board -active $app.Game.Active -ids $app.Game.Ids
    $app.Game.Active.Y = $ghost.Y
    $app.Engine.ForceLock()
    $app.NeedsDraw = $true
}