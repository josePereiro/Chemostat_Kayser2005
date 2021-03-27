import DrWatson: quickactivate
quickactivate(@__DIR__, "Chemostat_Kayser2005")

@time begin
    import SparseArrays
    import Base.Threads: @threads, threadid, SpinLock

    #  ----------------------------------------------------------------------------
    # Run add https://github.com/josePereiro/Chemostat_Kayser2005.jl in the Julia Pkg REPL to install the
    # package, then you must activate the package enviroment (see README)
    import Chemostat_Kayser2005
    const ChK = Chemostat_Kayser2005

    const iJR = ChK.iJR904
    const Kd = ChK.KayserData # experimental data
    const Bd = ChK.BegData    # cost data

    #  ----------------------------------------------------------------------------
    # run add "https://github.com/josePereiro/Chemostat" in the 
    # julia Pkg REPL for installing the package
    import Chemostat
    import Chemostat.LP.MathProgBase
    const Ch = Chemostat
    const ChU = Ch.Utils
    const ChLP = Ch.LP

    import JuMP, GLPK
    using Serialization
    import UtilsJL
    const UJL = UtilsJL
end

## -----------------------------------------------------------------------------------------------
const FBA_Z_FIX_MIN_COST    = :FBA_Z_FIX_MIN_COST
const FBA_MAX_BIOM_MIN_COST = :FBA_MAX_BIOM_MIN_COST
const FBA_Z_FIX_MIN_VG_COST = :FBA_Z_FIX_MIN_VG_COST
const FBA_Z_VG_FIX_MIN_COST = :FBA_Z_VG_FIX_MIN_COST
const EXPS = 5:13

## -----------------------------------------------------------------------------------------------
function base_model(exp)
    BASE_MODELS = ChU.load_data(iJR.BASE_MODELS_FILE; verbose = false);
    model_dict = BASE_MODELS["fva_models"][exp]
    model = ChU.MetNet(;model_dict...) |> ChU.uncompressed_model
end

## -----------------------------------------------------------------------------------------------
# Data container
LPDAT = UJL.DictTree()

## -----------------------------------------------------------------------------------------------
# FBA
let
    objider = iJR.KAYSER_BIOMASS_IDER
    costider = iJR.COST_IDER
    exglcider = iJR.GLC_EX_IDER
    max_sense = -1.0
    min_sense = 1.0

    iterator = Kd.val(:D) |> enumerate |> collect 
    for exp in EXPS

        @info("Doing ", exp); println()

        # FBA_MAX_BIOM_MIN_COST
        let
            model = base_model(exp)
            fbaout = ChLP.fba(model, objider, costider)
            
            LPDAT[FBA_MAX_BIOM_MIN_COST, :model, exp] = model
            LPDAT[FBA_MAX_BIOM_MIN_COST, :fbaout, exp] = fbaout
        end

        # FBA_Z_FIX_MIN_COST
        let
            model = base_model(exp)
            exp_growth = Kd.val("D", exp)
            ChU.bounds!(model, objider, exp_growth, exp_growth)
            fbaout = ChLP.fba(model, objider, costider)

            LPDAT[FBA_Z_FIX_MIN_COST, :model, exp] = model
            LPDAT[FBA_Z_FIX_MIN_COST, :fbaout, exp] = fbaout
        end

        # FBA_Z_FIX_MIN_VG_COST
        let
            model = base_model(exp)
            exp_growth = Kd.val("D", exp)
            ChU.bounds!(model, objider, exp_growth, exp_growth)
            fbaout1 = ChLP.fba(model, exglcider; sense = max_sense)
            exglc = ChU.av(model, fbaout1, exglcider)
            ChU.bounds!(model, exglcider, exglc, exglc)
            fbaout = ChLP.fba(model, costider; sense = min_sense)

            LPDAT[FBA_Z_FIX_MIN_VG_COST, :model, exp] = model
            LPDAT[FBA_Z_FIX_MIN_VG_COST, :fbaout, exp] = fbaout
        end

        # FBA_Z_VG_FIX_MIN_COST
        let
            model = base_model(exp)
            exp_growth = Kd.val("D", exp)
            ChU.bounds!(model, objider, exp_growth, exp_growth)
            exp_exglc = Kd.uval("GLC", exp)
            ChU.bounds!(model, exglcider, exp_exglc, exp_exglc)
            fbaout = ChLP.fba(model, costider; sense = min_sense)

            LPDAT[FBA_Z_VG_FIX_MIN_COST, :model, exp] = model
            LPDAT[FBA_Z_VG_FIX_MIN_COST, :fbaout, exp] = fbaout
        end
    end
end

## -------------------------------------------------------------------
ChU.save_data(iJR.LP_DAT_FILE, LPDAT)
