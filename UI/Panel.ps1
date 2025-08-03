# === PANEL BASE CLASS ===

class Panel {
    [int] $X
    [int] $Y
    [int] $Width
    [int] $Height
    [string] $Title

    hidden [hashtable] $__LastDrawnState = @{}

    Panel([int]$x, [int]$y, [int]$w, [int]$h, [string]$title = "") {
        $this.X = $x
        $this.Y = $y
        $this.Width = $w
        $this.Height = $h
        $this.Title = $title
    }

    [void] DrawFrame() {
        $frameKey = "$($this.X):$($this.Y):$($this.Width):$($this.Height):$($this.Title)"

        if ($this.__LastDrawnState.ContainsKey("frameKey") -and $this.__LastDrawnState["frameKey"] -eq $frameKey) {
            return  # Already drawn with same dimensions + title
        }

        $this.__LastDrawnState["frameKey"] = $frameKey

        $frameTop = "┌" + ("─" * $this.Width) + "┐"

        if ($this.Title) {
            $titleString = " $($this.Title) "
            $mid = [math]::Floor(($this.Width - $titleString.Length) / 2)
            $frameTop = "┌" + ("─" * $mid) + $titleString + ("─" * ($this.Width - $mid - $titleString.Length)) + "┐"
        }

        Write-CursorPositionIfChanged $this.X $this.Y
        [Console]::Write($frameTop)

        for ($row = 0; $row -lt $this.Height; $row++) {
            Write-CursorPositionIfChanged $this.X ($this.Y + 1 + $row)
            [Console]::Write("│")
            Write-CursorPositionIfChanged ($this.X + $this.Width + 1) ($this.Y + 1 + $row)
            [Console]::Write("│")
        }

        Write-CursorPositionIfChanged $this.X ($this.Y + $this.Height + 1)
        [Console]::Write("└" + ("─" * $this.Width) + "┘")
    }

    static [hashtable] GetMinMax([Point[]]$arr) {
        if (-not $arr -or $arr.Count -eq 0) {
            return @{ MinX = 0; MaxX = 0; MinY = 0; MaxY = 0 }
        }

        $minX = $maxX = $arr[0].X
        $minY = $maxY = $arr[0].Y
        foreach ($p in $arr) {
            if ($p.X -lt $minX) { $minX = $p.X }
            if ($p.X -gt $maxX) { $maxX = $p.X }
            if ($p.Y -lt $minY) { $minY = $p.Y }
            if ($p.Y -gt $maxY) { $maxY = $p.Y }
        }
        return @{ MinX = $minX; MaxX = $maxX; MinY = $minY; MaxY = $maxY }
    }
}