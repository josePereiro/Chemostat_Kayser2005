# DIRS
const KAYSER_RAW_DATA_DIR = joinpath(RAW_DATA_DIR, "Hayser2013")
const KAYSER_PROCESSED_DATA_DIR = joinpath(PROCESSED_DATA_DIR, basename(KAYSER_RAW_DATA_DIR))
const KAYSER_FIGURES_DIR = joinpath(FIGURES_DATA_DIR, basename(KAYSER_RAW_DATA_DIR))

function _create_dirs()
    for dir in [KAYSER_PROCESSED_DATA_DIR, KAYSER_FIGURES_DIR]
        try; mkpath(dir); catch err; @warn("Error creating dir", dir, err); end
    end
end

# FILES
const KAYSER_CONV_TABLE1_FILE = joinpath(KAYSER_PROCESSED_DATA_DIR, "table1_conv.bson")
const KAYSER_CONV_TABLE2_FILE = joinpath(KAYSER_PROCESSED_DATA_DIR, "table2_conv.bson")
const KAYSER_CONV_MEDIUM_FILE = joinpath(KAYSER_PROCESSED_DATA_DIR, "medium_conv.bson")
