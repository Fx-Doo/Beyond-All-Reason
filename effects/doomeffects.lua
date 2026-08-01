return {
  ["doomeffect"] = {
    radarpulse = {
      class              = [[CBitmapMuzzleFlame]],
      count              = 1,
      air                = true,
      ground             = true,
      water              = true,
      underwater         = true,
      properties = {
        colormap           = [[1 0.08 0.08 0.035    0.75 0.03 0.03 0.02    0 0 0 0.01]],
        dir                = [[0, 1, 0]],
        --gravity            = [[0.0, -0.4, 0.0]],
        frontoffset        = 0,
        fronttexture       = [[radarfx1]],
        length             = 45,
        sidetexture        = [[none]],
        size               = 14,
        sizegrowth         = 0.18,
        ttl                = 1,
        pos                = [[0, 5, 0]],
        rotParams          = [[-48, 32, -180 r360]],
        useairlos          = false,
      },
    },
  },

["targeteffect"] = {
    radarpulse = {
      class              = [[CBitmapMuzzleFlame]],
      count              = 1,
      air                = true,
      ground             = true,
      water              = true,
      underwater         = true,
      properties = {
        colormap           = [[0.10 1 0.18 0.03    0.04 0.75 0.10 0.018    0 0 0 0.01]],
        dir                = [[0, 1, 0]],
        --gravity            = [[0.0, -0.4, 0.0]],
        frontoffset        = 0,
        fronttexture       = [[radarfx1]],
        length             = 45,
        sidetexture        = [[none]],
        size               = 14,
        sizegrowth         = 0.26,
        ttl                = 1,
        pos                = [[0, 5, 0]],
        rotParams          = [[-48, 32, -180 r360]],
        useairlos          = false,
      },
    },
    },
}

