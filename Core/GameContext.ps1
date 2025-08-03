# === GAME CONTEXT & STATE CLASSES ===

class GameContext {
    [int] $Width
    [int] $Height
    [BitBoard] $Board
    [Tetromino] $Active
    [string[]] $NextQueue
    [int] $Score
    [int] $Lines
    [int] $Level
    [bool] $Paused
    [bool] $GameOver
    [string[]] $Ids
    [int[]] $GravityIntervals
    [hashtable] $PieceCounts

    GameContext([int]$width, [int]$height, [string[]]$ids, [int[]]$gInt) {
        $this.Width = $width
        $this.Height = $height
        $this.Ids = $ids
        $this.GravityIntervals = $gInt

        $this.Board = [BitBoard]::new()
        $this.Active = $null
        $this.NextQueue = @()
        $this.Score = 0
        $this.Lines = 0
        $this.Level = 0
        $this.Paused = $false
        $this.GameOver = $false

        # Initialize piece count stats
        $this.PieceCounts = @{}
        foreach ($id in $ids) {
            $this.PieceCounts[$id] = 0
        }
    }
}

class GameState {
    [System.UInt16[]] $Rows
    [string[,]]   $Ids
    [Tetromino]  $ActivePiece
    [Tetromino]  $GhostPiece
    [string]     $NextPieceId
    [int]        $Score
    [int]        $Lines
    [int]        $Level
    [bool]       $Paused
    [bool]       $GameOver
    [hashtable]  $PieceStats

    GameState(
        [BitBoard]      $board,
        [Tetromino]  $active,
        [Tetromino]  $ghost,
        [string]     $next,
        [int]        $score,
        [int]        $lines,
        [int]        $lvl,
        [bool]       $paused,
        [bool]       $go,
        [hashtable]  $pieceStats
    ) {
        $this.Rows        = $board.Rows.Clone()
        $this.Ids         = $board.Ids.Clone()
        $this.ActivePiece = $active
        $this.GhostPiece  = $ghost
        $this.NextPieceId = $next
        $this.Score       = $score
        $this.Lines       = $lines
        $this.Level       = $lvl
        $this.Paused      = $paused
        $this.GameOver    = $go
        $this.PieceStats  = $pieceStats.Clone()
    }
}