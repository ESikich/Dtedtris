# === INPUT MANAGER ===

class InputManager {
    [hashtable] $HeldKeys = @{}
    [int]       $DASDelay
    [int]       $DASInterval

    InputManager([int]$delay,[int]$interval) {
        $this.DASDelay    = $delay
        $this.DASInterval = $interval
    }

    [PlayerAction[]] GetActions() {
        $actions = @()
        $now = [Environment]::TickCount

        # Process new key presses
        while ([Console]::KeyAvailable) {
            $kinfo = [Console]::ReadKey($true)
            $k = $kinfo.Key

            if (-not $this.HeldKeys.ContainsKey($k)) {
                switch ($k) {
                    'LeftArrow'  { $actions += [PlayerAction]::Left     }
                    'RightArrow' { $actions += [PlayerAction]::Right    }
                    'DownArrow'  { $actions += [PlayerAction]::SoftDrop }
                    'UpArrow'    { $actions += [PlayerAction]::RotateCW }
                    'Spacebar'   { $actions += [PlayerAction]::HardDrop }
                    'P'          { $actions += [PlayerAction]::Pause    }
                    'Escape'     { $actions += [PlayerAction]::Quit     }
                }

                # Track for DAS repeat
                $this.HeldKeys[$k] = @{
                    PressedAt = $now
                    LastFired = $now
                }
            }
        }

        # Process DAS repeats
        foreach ($k in @($this.HeldKeys.Keys)) {
            $info = $this.HeldKeys[$k]
            if (-not $info -or -not $info.ContainsKey('PressedAt')) {
                continue
            }

            $elapsed   = $now - $info.PressedAt
            $sinceLast = $now - $info.LastFired

            $fireable  = ($k -eq 'DownArrow' -and $sinceLast -ge $this.DASInterval) -or
                         ($k -ne 'DownArrow' -and $elapsed -ge $this.DASDelay -and
                                                $sinceLast -ge $this.DASInterval)

            if ($fireable) {
                switch ($k) {
                    'LeftArrow'  { $actions += [PlayerAction]::Left     }
                    'RightArrow' { $actions += [PlayerAction]::Right    }
                    'DownArrow'  { $actions += [PlayerAction]::SoftDrop }
                }
                $info.LastFired = $now
            }
        }

        # Clear state if no keys are held (debounced)
        if (-not [Console]::KeyAvailable -and $this.HeldKeys.Count -gt 0) {
            $this.HeldKeys.Clear()
        }
        return $actions
    }
}