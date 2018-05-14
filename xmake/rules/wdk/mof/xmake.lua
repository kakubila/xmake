--!A cross-platform build utility based on Lua
--
-- Licensed to the Apache Software Foundation (ASF) under one
-- or more contributor license agreements.  See the NOTICE file
-- distributed with this work for additional information
-- regarding copyright ownership.  The ASF licenses this file
-- to you under the Apache License, Version 2.0 (the
-- "License"); you may not use this file except in compliance
-- with the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- 
-- Copyright (C) 2015 - 2018, TBOOX Open Source Group.
--
-- @author      ruki
-- @file        xmake.lua
--

-- define rule: *.mof
rule("wdk.mof")

    -- add rule: wdk environment
    add_deps("wdk.env")

    -- set extensions
    set_extensions(".mof")

    -- on load
    on_load(function (target)

        -- imports
        import("core.project.config")
        import("lib.detect.find_program")

        -- get arch
        local arch = assert(config.arch(), "arch not found!")

        -- get mofcomp
        local mofcomp = find_program("mofcomp", {check = function (program) 
            local tmpmof = os.tmpfile() 
            io.writefile(tmpmof, "")
            os.run("%s %s", program, tmpmof)
            os.tryrm(tmpmof)
        end})
        assert(mofcomp, "mofcomp not found!")
        
        -- get wmimofck
        local wmimofck = path.join(target:data("wdk").bindir, "x86", arch, is_host("windows") and "wmimofck.exe" or "wmimofck")
        assert(wmimofck and os.isexec(wmimofck), "wmimofck not found!")
        
        -- save mofcomp and wmimofck
        target:data_set("wdk.mofcomp", mofcomp)
        target:data_set("wdk.wmimofck", wmimofck)

        -- save output directory
        target:data_set("wdk.mof.outputdir", path.join(config.buildir(), ".wdk", "mof", config.get("mode") or "generic", config.get("arch") or os.arch(), target:name()))
    end)

    -- before build file
    before_build_file(function (target, sourcefile, opt)

        -- imports
        import("core.base.option")
        import("core.project.depend")

        -- get mofcomp
        local mofcomp = target:data("wdk.mofcomp")

        -- get wmimofck
        local wmimofck = target:data("wdk.wmimofck")

        -- get output directory
        local outputdir = target:data("wdk.mof.outputdir")

        -- add includedirs
        target:add("includedirs", outputdir)

        -- get header file
        local headerfile = path.join(outputdir, path.basename(sourcefile) .. ".h")

        -- get some temporary file 
        local sourcefile_mof     = path.join(outputdir, path.filename(sourcefile))
        local targetfile_mfl     = path.join(outputdir, "." .. path.basename(sourcefile) .. ".mfl")
        local targetfile_mof     = path.join(outputdir, "." .. path.basename(sourcefile) .. ".mof")
        local targetfile_mfl_mof = path.join(outputdir, "." .. path.basename(sourcefile) .. ".mfl.mof")
        local targetfile_bmf     = path.join(outputdir, path.basename(sourcefile) .. ".bmf")
        local outputdir_htm      = path.join(outputdir, "htm")
        local targetfile_vbs     = path.join(outputdir, path.basename(sourcefile) .. ".vbs")

        -- add clean files
        target:data_add("wdk.cleanfiles", {headerfile, sourcefile_mof, targetfile_mfl, targetfile_mof})
        target:data_add("wdk.cleanfiles", {targetfile_mfl_mof, targetfile_bmf, outputdir_htm, targetfile_vbs})

        -- need build this object?
        local dependfile = target:dependfile(headerfile)
        local dependinfo = option.get("rebuild") and {} or (depend.load(dependfile) or {})
        if not depend.is_changed(dependinfo, {lastmtime = os.mtime(headerfile), values = args}) then
            return 
        end

        -- trace progress info
        if option.get("verbose") then
            cprint("${green}[%02d%%]:${dim} compiling.wdk.mof %s", opt.progress, sourcefile)
        else
            cprint("${green}[%02d%%]:${clear} compiling.wdk.mof %s", opt.progress, sourcefile)
        end

        -- ensure the output directory
        if not os.isdir(outputdir) then
            os.mkdir(outputdir)
        end

        -- copy *.mof to output directory
        os.cp(sourcefile, sourcefile_mof)

        -- do mofcomp
        os.vrunv(mofcomp, {"-Amendment:ms_409", "-MFL:" .. targetfile_mfl, "-MOF:" .. targetfile_mof, sourcefile_mof})

        -- do wmimofck
        os.vrunv(wmimofck, {"-y" .. targetfile_mof, "-z" .. targetfile_mfl, targetfile_mfl_mof})

        -- do mofcomp to generate *.bmf
        os.vrunv(mofcomp, {"-B:" .. targetfile_bmf, targetfile_mfl_mof})

        -- do wmimofck to generate *.h
        os.vrunv(wmimofck, {"-h" .. headerfile, "-w" .. outputdir_htm, "-m", "-t" .. targetfile_vbs, targetfile_bmf})

        -- update files and values to the dependent file
        dependinfo.files  = {sourcefile}
        dependinfo.values = args
        depend.save(dependinfo, dependfile)
    end)
