-- Inclusion list only, same convention as every other abilities/data/*.lua
-- file -- no mechanical value duplicated here. DESOLATELAND/PRIMORDIALSEA
-- are still real national_dex kind="set_weather" records (weather="sun"/
-- "rain" respectively), read live exactly like Phase 1's plain weather
-- abilities. DELTASTREAM is the one genuine exception in this whole
-- abilities/ tree so far: its own record is kind="other" (confirmed by
-- direct read), because the weather value it sets ("a mysterious air
-- current") isn't in national_dex's own sun/rain/sandstorm/hail/snow
-- vocabulary at all -- there is no field to read it FROM. Its target value
-- (STRONGWINDS) is hardcoded in the engine file that dispatches this list,
-- not duplicated data (nothing to duplicate exists), consistent with "if
-- the label doesn't exist, we make our own."
return {
  DESOLATELAND = true,
  PRIMORDIALSEA = true,
  DELTASTREAM = true,
}
