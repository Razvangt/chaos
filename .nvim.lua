
local ctx = require('exrc').init()
local overseer = require('overseer')


overseer.register_template{
  name = 'run app',
  condition = {dir = ctx.exrc_dir},
  builder = function (params)
    return {
      name = "run",
      cwd = ctx.exrc_dir,
      cmd = 'lua scripts/run.lua',
      components = { { "on_output_quickfix", open = true }, "default" },
    }
    
  end
}


overseer.register_template{
  name = 'build_app',
  condition = {dir = ctx.exrc_dir},
  builder = function (params)
    return {
      name = "build",
      cwd = ctx.exrc_dir,
      cmd = 'lua scripts/build.lua',
      components = { { "on_output_quickfix", open = true }, "default" },
    }
    
  end
}

