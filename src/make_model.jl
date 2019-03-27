
function make_model(in_path::AbstractString; out_path="./autogeneratedmodel",
                    host="bacteria", model="Kinetics", lang="julia")

  # default argument names
  InPath = in_path
  OutPath = out_path
  Host = host
  Model = model
  Lang = lang

  path_head = Base.@__DIR__
  # Error report: line number --> error message
  error_report = Dict{Int64, Array}()


  # include(joinpath(path_head, "preprocessor3.jl"))
  # include("preprocessor3.jl")
  println("\n---------loading sentences------------")
  # inputSentencesArray = Array of pairs of (line, line #)
  inputSentencesArray = getRidOfNewlineHashcommentBlankline(InPath)
  println("\n>>>>>tokenizing sentences" * ">"^10)
  # tokenizedInputSentencesArray = Array of pairs of (tokens, line #)
  tokenizedInputSentencesArray = sentenceTokenization2(inputSentencesArray)
  println("\n>>>>>normalizing and tagging" * ">"^10)
  reservedWordsPath = joinpath(path_head, "reservedWords.jl")
  # reservedWordsPath = "reservedWords.jl"
  # taggedSentencesArray = Array of pairs of (taggedTokens, line #)
  taggedSentencesArray = tokenClassification2(tokenizedInputSentencesArray, reservedWordsPath)
  # reshape for output observation
  printTagSen = [["$(y[1])/$(y[2])" for y in x] for (x, id) in taggedSentencesArray]
  # println(typeof(printTagSen))
  foreach(println, [join(ts, "  ") for ts in printTagSen])


  # include(joinpath(path_head, "biosymDecoder.jl"))
  # include("biosymDecoder.jl")
  println("\n------------information extraction------------")
  include(reservedWordsPath)
  # BioSymVerbInfo = Array of pairs of ((senType, line#), BioSym, paraSet)
  BioSymVerbInfo = extractBioSymVerbInformation(taggedSentencesArray,
                   reservedWords["SentenceType"], error_report)
  # println("print by foreach:")
  foreach(println, BioSymVerbInfo)
  println("\n>>>>>decoding bio symbols" * ">"^10)
  decodingBioSymGroups(BioSymVerbInfo, error_report)
  # BioSymVerbInfo = Array of pairs of ((senType, line#), BioSym, paraSet)
  println("\n>>>>>decoding bio symbols results" * ">"^10)
  printArrayOfTripleToken(BioSymVerbInfo, AbstractString)
  println("\n>>>>>type conversion dictionary" * ">"^10)
  typeConversionDict = setUpSymbolConvertionDict(BioSymVerbInfo, error_report)
  foreach(println, typeConversionDict)
  println("\n>>>>>replace each biosymbol string with generalBioSym
          composite" * ">"^10)
  # newVerbBiosymInfo = Array of ((senType, line#), BioSym, paraSet)
  newVerbBiosymInfo = replaceEachBioSymWithGeneralBioSym(BioSymVerbInfo,
                      typeConversionDict, error_report)
  printArrayOfTripleToken(newVerbBiosymInfo, generalBioSym)


  # include(joinpath(path_head, "semanticChecking.jl"))
  # include("semanticChecking.jl")
  println("\n------------right before IR generation-----------------")
  # preIR_DS = array of tuple ((verb, line #), reactant, product, catalyst)
  preIR_DS = semanticCheckingForEachTriplet(newVerbBiosymInfo,
             typeConversionDict, error_report)
  printArrayOfTripleToken(preIR_DS, generalBioSym)

  #######################
  # TO HERE, no more error report after this line
  #######################
  # print errors
  if length(error_report) != 0
    println("\n\n\n#################### Error report: Useful tips ########")
    for lineNum in sort(collect(keys(error_report)))
      println("in line $lineNum -->", )
      for err in error_report[lineNum]
        println("\t$(err)")
      end
    end
    exit()
  end


  println("\n------------model generation preparation------------------")
  # include(joinpath(path_head, "modelGeneration.jl"))
  # include("modelGeneration.jl")
  sys2userDict = Dict()
  for (key, val) in typeConversionDict
    sys2userDict[val] = key
  end
  # reform to match with NML_V1
  # preIR_DS = array of tuple ((verb, line #), [reactant, product, catalyst])
  (rnx, txtl, rnx_set, mRNA_set, m_protein_set) = preparing_rnxList_txtlDict(
    preIR_DS, sys2userDict, typeConversionDict)

  println(">>>>>rnx list" * ">"^10)
  foreach(x->println(x.rnxName), rnx)
  # Sorting, insert "BIOMASS" here
  (sorted_rnx_species_array, rnx_species2index_dict, rnx_index2species_dict,
   sorted_all_species_array, all_species2index_dict, all_index2species_dict, extra_species_num) =
    sorting_species_list(rnx_set, mRNA_set, m_protein_set, sys2userDict)
  println("------------")
  foreach(println, sorted_rnx_species_array)
  println("------------")
  foreach(println, sorted_all_species_array)

  # write program to disk
  output_file = Dict{String, String}()  # put all files in this dict
  # stoichiometric_matrix
  stoichiometric_matrix_buffer = build_stoichiometric_matrix_buffer(rnx, rnx_species2index_dict)
  output_file["stoichiometry.dat"] = stoichiometric_matrix_buffer

  println("\n------------Modeling Framework-----")
  # DISTRIBUTION file mapping
  DISTRIBUTION = Dict(
      "julia"   => ("distribution/dis.jl", "JuliaStrategy.jl"),
      "python2" => ("distribution/dis.py2", "Python2Strategy.jl"),
      "python"  => ("distribution/dis.py3", "Python3Strategy.jl"),
      "python3" => ("distribution/dis.py3", "Python3Strategy.jl"),
      "matlab"  => ("distribution/dis.m", "MATLABStrategy.jl")
  )
  target_lang = Lang
  model_frame = Model
  if target_lang == "julia"
    # include(joinpath(path_head, DISTRIBUTION["julia"][2]))
    fn_prefix = "jl_"
    file_suffix = ".jl"
    dis_file_folder = DISTRIBUTION["julia"][1]
  elseif ((target_lang == "python3") || (target_lang == "python"))
    # include(joinpath(path_head, DISTRIBUTION["python3"][2]))
    fn_prefix = "py3_"
    file_suffix = ".py"
    dis_file_folder = DISTRIBUTION["python3"][1]
  elseif target_lang == "python2"
    # include(joinpath(path_head, DISTRIBUTION["python2"][2]))
    fn_prefix = "py2_"
    file_suffix = ".py"
    dis_file_folder = DISTRIBUTION["python2"][1]
  elseif  target_lang == "matlab"
    # include(joinpath(path_head, DISTRIBUTION["matlab"][2]))
    fn_prefix = "m_"
    file_suffix = ".m"
    dis_file_folder = DISTRIBUTION["matlab"][1]
  else
    println("Generate model in julia as default")
    # include(joinpath(path_head, DISTRIBUTION["julia"][2]))
    fn_prefix = "jl_"
    target_lang = "julia"
    file_suffix = ".jl"
    dis_file_folder = DISTRIBUTION["julia"][1]
  end

  fnmap = Dict(
      "julia"   => (jl_build_kinetics_buffer, jl_build_data_dictionary_buffer,
                    jl_build_simulation_buffer, jl_build_solveODEBalances_buffer,
                    jl_generate_FBA_data_dictionary),
      "python2" => (py2_build_kinetics_buffer, py2_build_data_dictionary_buffer,
                    py2_build_simulation_buffer, py2_build_solveODEBalances_buffer,
                    py2_generate_FBA_data_dictionary),
      "python" => (py3_build_kinetics_buffer, py3_build_data_dictionary_buffer,
                    py3_build_simulation_buffer, py3_build_solveODEBalances_buffer,
                    py3_generate_FBA_data_dictionary),
      "python3" => (py3_build_kinetics_buffer, py3_build_data_dictionary_buffer,
                    py3_build_simulation_buffer, py3_build_solveODEBalances_buffer,
                    py3_generate_FBA_data_dictionary),
      "matlab"  => (m_build_kinetics_buffer, m_build_data_dictionary_buffer,
                    m_build_simulation_buffer, m_build_solveODEBalances_buffer,
                    m_generate_FBA_data_dictionary)
  )

  # Generate FBA model
  if model_frame in ["FBA", "FVA"]
    if target_lang == "matlab"
        data_dictionary_buffer, maximize_product_buffer = fnmap[target_lang][5](
               rnx, sorted_rnx_species_array, extra_species_num)
        output_file["DataDictionary" * file_suffix] = data_dictionary_buffer
        output_file["maximizeProductDictionary" * file_suffix] = maximize_product_buffer
    else
        data_dictionary_buffer = fnmap[target_lang][5](rnx,
                                   sorted_rnx_species_array, extra_species_num)
        output_file["DataDictionary" * file_suffix] = data_dictionary_buffer
    end
    # write & copy
    output_dir = OutPath
    if !(isdir(output_dir))
      mkpath(output_dir)
    end
    for (file_name, file) in output_file
      write(joinpath(output_dir, file_name), file)
    end
    for file in readdir(joinpath(path_head, dis_file_folder))
      if occursin(file_suffix, file)
          println(file)
          f = joinpath(path_head, dis_file_folder, file)
          cp(f, joinpath(output_dir, file); force=true)
      end
    end
    cp(InPath, joinpath(output_dir, basename(InPath)); force=true)
  # Generate Kinetic model
  else
    (kinetics_buffer, Monod_const, W_array, disassociation_const) =
      fnmap[target_lang][1](all_species2index_dict, rnx, txtl, sys2userDict)
    output_file["Kinetics" * file_suffix] = kinetics_buffer

    host_type = Host
    data_dictionary_buffer = fnmap[target_lang][2](host_type, sorted_all_species_array,
      all_species2index_dict,
      sorted_rnx_species_array, rnx, txtl, Monod_const, W_array, disassociation_const,
      collect(mRNA_set), collect(m_protein_set))
    output_file["DataDictionary" * file_suffix] = data_dictionary_buffer

    ODE_simulation_buffer = fnmap[target_lang][3](extra_species_num)
    output_file["Balances" * file_suffix] = ODE_simulation_buffer

    solveODEBalances_buffer = fnmap[target_lang][4](sorted_all_species_array,
      all_species2index_dict, collect(mRNA_set), collect(m_protein_set))
    output_file["SolveBalances" * file_suffix] = solveODEBalances_buffer

    output_dir = OutPath
    if !(isdir(output_dir))
      mkpath(output_dir)
    end
    if target_lang == "julia"
      cp(joinpath(path_head, "include.jl"), joinpath(output_dir, "include.jl"); force=true)
    end
    cp(InPath, joinpath(output_dir, basename(InPath)); force=true)
    for (file_name, file) in output_file
      write(joinpath(output_dir, file_name), file)
    end
  end

end
