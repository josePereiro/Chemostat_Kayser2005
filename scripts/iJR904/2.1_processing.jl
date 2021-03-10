import DrWatson: quickactivate
quickactivate(@__DIR__, "Chemostat_Kayser2005")

@time begin
    import SparseArrays
    import Base.Threads: @threads, threadid

    # -------------------------------------------------------------------
    # Run add https://github.com/josePereiro/Chemostat_Kayser2005.jl in 
    # the Julia Pkg REPL to install the package, then you must activate 
    # the package enviroment (see README)
    import Chemostat_Kayser2005
    const ChK = Chemostat_Kayser2005
    const iJR = ChK.iJR904
    const Kd = ChK.KayserData # experimental data
    const Bd = ChK.BegData    # cost data

    # -------------------------------------------------------------------
    # run add "https://github.com/josePereiro/Chemostat" in the 
    # julia Pkg REPL for installing the package
    import Chemostat
    import Chemostat.LP.MathProgBase
    const Ch = Chemostat
    const ChU = Ch.Utils
    const ChSS = Ch.SteadyState
    const ChLP = Ch.LP
    const ChEP = Ch.MaxEntEP
    const ChSU = Ch.SimulationUtils

    import ChemostatPlots
    const ChP = ChemostatPlots
    
    import UtilsJL
    const UJL = UtilsJL

    using Serialization

    # -------------------------------------------------------------------
    using Plots, FileIO
    import GR
    GR.inline("png")

end

## -------------------------------------------------------------------
INDEX = ChU.load_data(iJR.MAXENT_VARIANTS_INDEX_FILE; verbose = false);

# -------------------------------------------------------------------
const ME_Z_OPEN_G_OPEN = :ME_Z_OPEN_G_OPEN
const ME_Z_EXPECTED_G_MOVING    = :ME_Z_EXPECTED_G_MOVING
const ME_Z_EXPECTED_G_BOUNDED = :ME_Z_EXPECTED_G_BOUNDED
const ME_Z_FIXXED_G_BOUNDED = :ME_Z_FIXXED_G_BOUNDED

ALL_MODELS = [ME_Z_OPEN_G_OPEN, ME_Z_EXPECTED_G_MOVING, ME_Z_EXPECTED_G_BOUNDED, ME_Z_FIXXED_G_BOUNDED]

# -------------------------------------------------------------------
fileid = "2.1"
function mysavefig(p, pname; params...)
    pname = string(fileid, "_", pname)
    fname = UJL.mysavefig(p, pname, iJR.MODEL_FIGURES_DIR; params...)
    @info("Plotting", fname)
end
myminmax(a::Vector) = (minimum(a), maximum(a))
CONC_IDERS = ["GLC", "AC", "NH4"]
FLX_IDERS = ["GLC", "CO2", "O2", "AC", "NH4"]

exp_colors = let EXPS = 1:13
    colors = Plots.distinguishable_colors(length(EXPS))
    Dict(exp => color for (exp, color) in zip(EXPS, colors))
end

ider_colors = Dict(
    "GLC" => :red, "CO2" => :yellow,
    "O2" => :blue, "AC" => :orange, 
    "NH4" => :green, "D" => :black,
)

method_colors = Dict(
    ME_Z_OPEN_G_OPEN => :red,
    ME_Z_EXPECTED_G_BOUNDED => :orange,
    ME_Z_FIXXED_G_BOUNDED => :blue,
)

## -------------------------------------------------------------------
# Collect
DAT = ChU.DictTree()
let 
    # CACHE
    DATfile = joinpath(iJR.MODEL_PROCESSED_DATA_DIR, "2.1_DAT.jls")
    if isfile(DATfile) 
        global DAT = deserialize(DATfile) 
        @info("DAT CACHE LOADED")
        return
    end
    DAT[:EXPS] = []

    objider = iJR.KAYSER_BIOMASS_IDER
    DAT[:CONC_IDERS] = CONC_IDERS
    DAT[:FLX_IDERS] = FLX_IDERS

    exch_met_map = iJR.load_exch_met_map()
    Kd_mets_map = iJR.load_mets_map()

    # Find exps
    for exp in 1:13
        ok = false
        for method in ALL_MODELS
            ok = haskey(INDEX, method, :DFILE, exp) &&
                INDEX[method, :DFILE, exp] != :unfeasible
            !ok && break
        end
        !ok && continue
        push!(DAT[:EXPS], exp)
    end

    ps_pool = Dict()
    for exp in DAT[:EXPS], method in ALL_MODELS
            
        !haskey(INDEX, method, :DFILE, exp) && continue
        datfile = INDEX[method, :DFILE, exp]

        dat = deserialize(datfile)
        
        model = dat[:model]
        objidx = ChU.rxnindex(model, objider)
        epouts = dat[:epouts]
        exp_beta = maximum(keys(epouts))
        epout = epouts[exp_beta]
        exp_xi = Kd.val(:xi, exp)

        println()
        @info("Doing", exp, method, length(dat[:epouts]), epout.iter);

        # Biomass
        ep_biom = ChU.av(model, epout, objidx)
        ep_std = sqrt(ChU.va(model, epout, objidx))
        Kd_biom = Kd.val("D", exp)
        
        # store
        DAT[method, :ep   , :flx, objider, exp] = ep_biom
        DAT[method, :eperr, :flx, objider, exp] = ep_std
        DAT[method, :Kd   , :flx, objider, exp] = Kd_biom
        DAT[:Kd   , :flx, objider, exp] = Kd_biom
        DAT[method, :fva  , :flx, objider, exp] = ChU.bounds(model, objider)
        
        # fuxes
        for Kd_met in FLX_IDERS

                model_met = Kd_mets_map[Kd_met]
                model_exch = exch_met_map[model_met]
                model_exchi = ChU.rxnindex(model, model_exch)

                proj = ChLP.projection2D(model, objider, model_exchi; l = 50)
                ep_av = ChU.av(model, epout, model_exchi)
                ep_std = sqrt(ChU.va(model, epout, model_exchi))
                Kd_flx = Kd.val("u$Kd_met", exp)
                
                DAT[method, :Kd, :flx, Kd_met, exp] = Kd_flx
                DAT[:Kd, :flx, Kd_met, exp] = Kd_flx
                DAT[method, :ep, :proj, Kd_met, exp] = proj
                DAT[method, :ep, :flx, Kd_met, exp] = ep_av
                DAT[method, :eperr, :flx, Kd_met, exp] = ep_std
                
                DAT[method, :fva , :flx, Kd_met, exp] = ChU.bounds(model, model_exch)

        end

        # mets
        for Kd_met in CONC_IDERS

            ep_std = DAT[method, :eperr, :flx, Kd_met, exp] 
            ep_av = DAT[method, :ep, :flx, Kd_met, exp]
            # conc (s = c + u*xi)
            c = Kd.val("c$Kd_met", exp, 0.0)
            ep_conc = max(c + ep_av * exp_xi, 0.0)
            Kd_conc = Kd.val("s$Kd_met", exp)

            DAT[method, :Kd, :conc, Kd_met, exp] = Kd_conc
            DAT[:Kd, :conc, Kd_met, exp] = Kd_conc
            DAT[method, :ep, :conc, Kd_met, exp] = ep_conc
            DAT[method, :eperr, :conc, Kd_met, exp] = ep_std * exp_xi
        end

    end # for exp in EXPS, for method

    # saving
    DAT[:EXPS] |> unique! |> sort!
    serialize(DATfile, DAT)
end
EXPS = DAT[:EXPS]

## -------------------------------------------------------------------
# Inter project comunication
let
    CORR_DAT = isfile(iJR.CORR_DAT_FILE) ? ChU.load_data(iJR.CORR_DAT_FILE) : Dict()
    CORR_DAT[:MAXENT_EP] = DAT
    ChU.save_data(iJR.CORR_DAT_FILE, CORR_DAT)
end

## -------------------------------------------------------------------
# proj 2D
let
    method = ME_Z_EXPECTED_G_MOVING
    biom_ider = iJR.KAYSER_BIOMASS_IDER

    ps_pool = Dict()
    for exp in EXPS

        datfile = INDEX[method, :DFILE, exp]
        dat = deserialize(datfile)
        
        model = dat[:model]
        
        for Kd_ider in FLX_IDERS

            # 2D Projection
            p = plot(;title = string("Kayser2005 exp:", exp), 
                xlabel = string(biom_ider), ylabel = string(Kd_ider),
                legend = :left
            )
            proj = DAT[method, :ep, :proj, Kd_ider, exp]
            ChP.plot_projection2D!(p, proj; l = 50)

            # cgD/X
            input = -Kd.cval(Kd_ider, exp, 0.0) * Kd.val(:D, exp) / Kd.val(:Xv, exp)
            hline!(p, [input]; lw = 3, color = :black, ls = :solid, label = "input")

            # EXPERIMENTAL FLXS
            exp_biom = DAT[method, :Kd, :flx, biom_ider, exp]
            exp_exch = DAT[method, :Kd, :flx, Kd_ider, exp]
            scatter!(p, [exp_biom], [exp_exch]; 
                m = 8, color = :red, label = "exp"
            )
            
            # MAXENT FLXS
            ep_biom = DAT[method, :ep, :flx, biom_ider, exp]
            ep_biom_err = DAT[method, :eperr, :flx, biom_ider, exp]
            ep_exch = DAT[method, :ep, :flx, Kd_ider, exp]
            ep_exch_err = DAT[method, :eperr, :flx, Kd_ider, exp]
            scatter!(p, [ep_biom], [ep_exch]; 
                xerr = [ep_biom_err], yerr = [ep_exch_err],
                m = 8, color = :blue, label = "maxent"
            )

            # mysavefig(p, "polytope"; Kd_ider, exp, method)
            ps_pool[(exp, Kd_ider)] = deepcopy(p)
        end
    end

    # collect 
    for exp in EXPS
        ps = Plots.Plot[ps_pool[(exp, Kd_ider)] for Kd_ider in FLX_IDERS]
        mysavefig(ps, "polytope"; exp, method)
    end

    for Kd_ider in FLX_IDERS
        ps = Plots.Plot[ps_pool[(exp, Kd_ider)] for exp in EXPS]
        mysavefig(ps, "polytope"; Kd_ider, method)
    end
end

## -------------------------------------------------------------------
# beta vs stuff
let
    method = ME_Z_EXPECTED_G_MOVING
    cGLC_plt = plot(;xlabel = "cGLC", ylabel = "beta")
    D_plt = plot(;xlabel = "D", ylabel = "beta")
    for exp in EXPS 
        datfile = INDEX[method, :DFILE, exp]
        dat = deserialize(datfile)
        beta = maximum(keys(dat[:epouts]))

        params = (;label = "", color = exp_colors[exp], 
            alpha = 0.7, ms = 7
        )
        cGLC = Kd.val("cGLC", exp)
        D = Kd.val("D", exp)
        scatter!(cGLC_plt, [cGLC], [beta]; params...)
        scatter!(D_plt, [D], [beta]; params...)
    end
    mysavefig([cGLC_plt, D_plt], "beta_vs_stuff"; method)
end

## -------------------------------------------------------------------
# EP biomass corr
let
    objider = iJR.KAYSER_BIOMASS_IDER
    ps = Plots.Plot[]
    for method in ALL_MODELS
        p = plot(title = string(iJR.PROJ_IDER, " method: ", method), 
            xlabel = "model biom", ylabel = "exp biom")
        ep_vals = DAT[method, :ep, :flx, objider, EXPS]
        eperr_vals = DAT[method, :eperr, :flx, objider, EXPS]
        Kd_vals = DAT[method, :Kd, :flx, objider, EXPS]
        color = [exp_colors[exp] for exp in EXPS]
        m, M = myminmax([Kd_vals; ep_vals])
        margin = abs(M - m) * 0.1
        scatter!(p, ep_vals, Kd_vals; 
            xerr = eperr_vals,
            label = "", color,
            alpha = 0.7, ms = 7,
            xlim = [m - margin, M + margin],
            ylim = [m - margin, M + margin],
        )
        push!(ps, p)
    end
    layout = (1, length(ps))
    mysavefig(ps, "obj_val_ep_corr"; layout)
end

## -------------------------------------------------------------------
# flux vs beta
let
    objider = iJR.KAYSER_BIOMASS_IDER
    method = ME_Z_EXPECTED_G_MOVING
    p = plot(title = iJR.PROJ_IDER, xlabel = "beta", ylabel = "biom")
    for exp in EXPS 
        datfile = INDEX[method, :DFILE, exp]
        dat = deserialize(datfile)
        model = dat[:model]
        objidx = ChU.rxnindex(model, objider)
        epouts = dat[:epouts]
        exp_beta = maximum(keys(epouts))
        exp_xi = Kd.val("xi", exp)
        scatter!(p, [exp_beta], [Kd.val("D", exp)], ms = 12, color = :white, label = "")

        betas = collect(keys(epouts)) |> sort
        bioms = [ChU.av(model, epouts[beta], objidx) for beta in betas]
        scatter!(p, betas, bioms, label = "", color = :black, alpha = 0.2)

    end
    mysavefig(p, "obj_val_vs_beta"; method)
end

## -------------------------------------------------------------------
# total correlations
let
    for (dat_prefix, iders, zoom_lim) in [(:flx, FLX_IDERS, [-2.5, 2.5]), 
                                            (:conc, CONC_IDERS, [0.0, 100.0])]

        ps = Plots.Plot[]
        for method in ALL_MODELS                                     
            ep_vals = DAT[method, :ep, dat_prefix, iders, EXPS]
            ep_errs = DAT[method, :eperr, dat_prefix, iders, EXPS]
            Kd_vals = DAT[method, :Kd, dat_prefix, iders, EXPS]
            
            diffsign = sign.(Kd_vals) .* sign.(ep_vals)
            diffsign = ifelse.(diffsign .== 0, 1.0, diffsign)
            Kd_vals = abs.(Kd_vals) .* diffsign
            ep_vals = abs.(ep_vals) .* diffsign

            color = [ider_colors[ider] for ider in iders, exp in EXPS]
            m, M = myminmax([ep_vals; Kd_vals])

            scatter_params = (;label = "", color, ms = 7, alpha = 0.7)
            # ep corr
            p1 = plot(title = "$(iJR.PROJ_IDER) (EP) $method", 
                ylabel = "model signdiff $(dat_prefix)",
                xlabel = "exp signdiff $(dat_prefix)", 
            )
            scatter!(p1, Kd_vals, ep_vals; xerr = ep_errs, scatter_params...)
            plot!(p1, [m,M], [m,M]; ls = :dash, color = :black, label = "")
            push!(ps, deepcopy(p1))

        end

        layout = (1, length(ps))
        pname = string(dat_prefix, "_tot_corr")
        mysavefig(ps, pname; layout)
    end

end

## -------------------------------------------------------------------
# fva bounds
let
   
    ps = Plots.Plot[]
    for ider = FLX_IDERS
        p = plot(title = ider, xlabel = "replica", ylabel = "flx")
        xticks =  (EXPS, string.(EXPS))
        
        Kd_vals = DAT[:Kd, :flx, ider, EXPS]
        plot!(p, EXPS, Kd_vals; 
            label = "exp", color = :black, alpha = 0.8, lw = 3, xticks)

        for method in ALL_MODELS
            color = method_colors[method]    
            
            ep_vals = DAT[method, :ep, :flx, ider, EXPS]
            plot!(p, EXPS, ep_vals; 
                label = string(method), color, alpha = 0.5, lw = 5, ls = :dash, xticks)
            
            fva_ranges = DAT[method, :fva, :flx, ider, EXPS]
            plot!(p, EXPS, last.(fva_ranges);  
                label = "", color, alpha = 0.8, ls = :dot, lw = 3, xticks)
            plot!(p, EXPS, first.(fva_ranges); 
                label = "", color, alpha = 0.8, ls = :dot, lw = 3, xticks)
        end
        push!(ps, p)
    end
    pname = string("bound_study")
    mysavefig(ps, pname)
    
end

## -------------------------------------------------------------------
# marginal distributions
let 
    objider = iJR.KAYSER_BIOMASS_IDER
    size = [300, 250]
    Kd_mets_map = iJR.load_mets_map()
    exch_met_map = iJR.load_exch_met_map()

    # Iders
    model_iders, Kd_iders = [objider], ["D"]
    for Kd_met in CONC_IDERS
        model_met = Kd_mets_map[Kd_met]
        model_exch = exch_met_map[model_met]
        push!(model_iders, model_exch)
        push!(Kd_iders, string("u", Kd_met))
    end
    
    for (model_ider, Kd_ider) in zip(model_iders, Kd_iders)
        ps = Plots.Plot[]
        ps_bs = Plots.Plot[]
        for exp in EXPS
            p = plot(title = string(Kd_ider, " exp: ", exp))
            p_bs = plot(title = string(Kd_ider, " exp: ", exp))
            margin, m, M = -Inf, Inf, -Inf
            Kd_av = Kd.val(Kd_ider, exp)
            
            # EP
            for method in [ME_Z_EXPECTED_G_BOUNDED, ME_Z_FIXXED_G_BOUNDED, ME_Z_OPEN_G_OPEN]
                color = method_colors[method]    

                datfile = INDEX[method, :DFILE, exp]
                dat = deserialize(datfile)
                model = dat[:model]
                objidx = ChU.rxnindex(model, objider)
                epouts = dat[:epouts]
                exp_beta = maximum(keys(epouts))
                epout = epouts[exp_beta]
                ep_av = ChU.av(model, epout, model_ider)
                ep_va = sqrt(ChU.va(model, epout, model_ider))
                        
                ChP.plot_marginal!(p, model, [epout], model_ider; 
                    legend = false, color, alpha = 0.6, lw = 5)
                
                m = minimum([m, ep_av, Kd_av])
                M = maximum([M, ep_av, Kd_av])
                margin = maximum([margin, 3 * ep_va])

                if method == ME_Z_FIXXED_G_BOUNDED
                    for (beta, epout) in sort(epouts; by = first)
                        ep_av = ChU.av(model, epout, model_ider)
                        ep_va = sqrt(ChU.va(model, epout, model_ider))
                        
                        alpha = 0.15
                        color = method_colors[method]
                        ChP.plot_marginal!(p_bs, model, epout, model_ider; 
                            legend = false, color, alpha, lw = 1)

                        if beta == exp_beta
                            ChP.plot_marginal!(p_bs, model, epout, model_ider; 
                                legend = false, color, 
                                alpha = 1.0, lw = 3
                            )
                            break
                        end
                    end
                    push!(ps_bs, p_bs)
                end

            end
            # Experimental
            vline!(p, [Kd_av]; label = "", lw = 6, color = :black, alpha = 0.3)
            vline!(p_bs, [Kd_av]; label = "", lw = 6, color = :black, alpha = 0.3)
            
            plot!(p; xlim = [m - margin, M + margin], size)
            plot!(p_bs; xlim = [m - margin, M + margin], size)
            push!(ps, p)
        end

        for k in [:xi, :D, :sGLC]
            p = plot(;title = Kd_ider, size)
            xticks =  (EXPS, string.(EXPS))
            vals = [Kd.val(k, exp) for exp in EXPS]
            p = bar!(p, EXPS, vals; title = k, label = "", xticks)
            push!(ps, p)
            push!(ps_bs, p)
        end

        pname = string(Kd_ider, "_marginals")
        mysavefig(ps, pname)

        method = ME_Z_FIXXED_G_BOUNDED
        pname = string(Kd_ider, "_marginals_vs_beta")
        mysavefig(ps_bs, pname; method)
    end

end 

## -------------------------------------------------------------------
# marginals v2
let 
    objider = iJR.KAYSER_BIOMASS_IDER
    size = [300, 250]
    Kd_mets_map = iJR.load_mets_map()
    exch_met_map = iJR.load_exch_met_map()

    # Iders
    model_iders, Kd_iders = [objider], ["D"]
    for Kd_met in CONC_IDERS
        model_met = Kd_mets_map[Kd_met]
        model_exch = exch_met_map[model_met]
        push!(model_iders, model_exch)
        push!(Kd_iders, string("u", Kd_met))
    end
    
    for (model_ider, Kd_ider) in zip(model_iders, Kd_iders)
        marg_params = (;xlabel = string(Kd_ider), yaxis = nothing, ylabel = "prob")

        epps = Plots.Plot[]
        exps = Plots.Plot[]
        for method in [ME_Z_EXPECTED_G_BOUNDED, ME_Z_FIXXED_G_BOUNDED, ME_Z_OPEN_G_OPEN]
            expp = plot(;title = string("Experimental"), marg_params...)
            epp = plot(;title = string(" MaxEnt: ", method), marg_params...)
            margin, m, M = -Inf, Inf, -Inf
            
            # EP
            for exp in EXPS
                Kd_av = Kd.val(Kd_ider, exp)
                color = exp_colors[exp]    

                datfile = INDEX[method, :DFILE, exp]
                dat = deserialize(datfile)
                model = dat[:model]
                objidx = ChU.rxnindex(model, objider)
                epouts = dat[:epouts]
                exp_beta = maximum(keys(epouts))
                epout = epouts[exp_beta]
                ep_av = ChU.av(model, epout, model_ider)
                ep_va = sqrt(ChU.va(model, epout, model_ider))
                        
                ChP.plot_marginal!(epp, model, [epout], model_ider; 
                    legend = false, color, alpha = 0.8, lw = 3)
                
                m = minimum([m, ep_av, Kd_av])
                M = maximum([M, ep_av, Kd_av])
                margin = maximum([margin, 3 * ep_va])

                # Experimental
                vline!(expp, [Kd_av]; label = "", lw = 3, color, alpha = 0.8)
                
            end
            
            map([expp, epp]) do p
                plot!(p; xlim = [m - margin, M + margin], size)
            end

            push!(epps, epp)
            push!(exps, expp)
        end

        extras = Plots.Plot[]
        for k in [:xi, :D, :sGLC]
            p = plot(;title = "Experimental", size, 
                xlabel = "rep", ylabel = string(k))
            xticks =  (EXPS, string.(EXPS))
            vals = [Kd.val(k, exp) for exp in EXPS]
            color = [exp_colors[exp] for exp in EXPS]
            p = bar!(p, EXPS, vals; label = "", xticks, color)
            push!(extras, p)
        end

        ps = Plots.Plot[exps; epps; extras]
        layout = (3, 3)
        pname = string(Kd_ider, "_marginals_v2")
        mysavefig(ps, pname; layout)

    end # for (model_ider, Kd_ider)

end 

## -------------------------------------------------------------------
# leyends
# TODO fix this...
let
    for (title, colors) in [
            ("exp", exp_colors), 
            ("iders", ider_colors),
            ("method", method_colors)
        ]
    p = plot(; framestyle = :none)
        scolors = sort(collect(colors); by = (p) -> string(first(p)))
        for (id, color) in scolors
            scatter!(p, [0], [0];
                thickness_scaling = 1,
                color, ms = 8, label = string(id),
                legendfontsize=10, 
                # size = [300, 900],
                # legend = :left
            )
        end
        mysavefig(p, "$(title)_color_legend")
    end
end