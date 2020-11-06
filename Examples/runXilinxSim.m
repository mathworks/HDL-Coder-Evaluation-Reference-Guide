%
% Copyright 2020 The MathWorks, Inc.
%
function runXilinxSim(dutPath,varargin)
% RUNXILINXSIM  Generates HDL and testbench, and runs HDL simulation using 
%               Xilinx Vivado Simulator or ISIM
%
%   RUNXILINXSIM(DUTPATH) sets HDL properties to generate compilation and
%   simulation scripts for use with Vivado Simulator. The function
%   generates HDL and testbench for DUTPATH, and simulates the generated
%   files in Vivado Simulator.
%   
%   DUTPATH should be a subsystem with a legal HDL name (contains only
%   alpha-numeric or underscore).
%
%   RUNXILINXSIM(DUTPATH,TOOLNAME) generates scripts and runs HDL
%   simulation using the simulator specified in TOOLNAME. TOOLNAME can be
%   'ISIM' or 'Vivado'.
%
%   Note: 
%   You must manually set up Xilinx tool paths for launching ISIM/Vivado
%   Simulator from MATLAB. Example:
%
%   >> hdlsetuptoolpath('ToolName', 'Xilinx Vivado', ...
%   'ToolPath', 'C:\Xilinx\Vivado\2016.4\bin');

try
    model = bdroot(dutPath);
    dut   = get_param(dutPath, 'Name');
    assert(~isempty(model));
catch me
    error(['Error getting model name. Make sure model is open, '...
        'and %s is a valid DUT path.'], dutPath);
end

if ~isempty(regexp(dut, '\W', 'match'))
    error('DUT name "%s" is not a legal HDL name.' ,dut);
end

if nargin == 1
    toolName = 'Vivado';
elseif nargin == 2
    toolName = varargin{:};
    if ~any(strcmpi(toolName, {'ISIM','Vivado'}))
        error('Second input argument TOOLNAME should be ISIM or Vivado');
    end
else
    error('Too many input arguments. Expecting DUTPATH and TOOLNAME only.');
end
    
% Set HDL Coder properties to generate compilation/simulation scripts
isimPrjPostfix = '_xsim.prj';
isimTclPostfix = '_xsim.tcl';

if isequal(toolName,'ISIM') % ISIM
    add_wave_cmd = 'wave add %s\n';
    CompilerSelect = 'fuse';
    SimulatorSelect = 'x.exe';
    CompileCmdArg = '' ;
    SimCmdArg = '';
else % Vivado
    add_wave_cmd = 'add_wave %s\n';
    CompilerSelect = 'xelab';
    SimulatorSelect = 'xsim';
    CompileCmdArg = [' -debug wave' ' -s MySim'];
    SimCmdArg = ' MySim';
end

params_isim = {'HDLCompileFilePostfix', isimPrjPostfix, ...
               'HDLCompileInit', '', ...
               'HDLCompileVHDLCmd', 'vhdl work %s %s\n', ...
               'HDLCompileVerilogCmd', 'verilog work %s %s\n', ...
               'HDLSimFilePostfix', isimTclPostfix, ...
               'HDLSimInit', '', ...
               'HDLSimCmd', '', ...
               'HDLSimViewWaveCmd', add_wave_cmd, ...
               'HDLSimTerm', 'run all\n'};

% Get folder, language and set test bench properties 
targetDir  = hdlget_param(model,'TargetDirectory');
targetLang = hdlget_param(model,'TargetLanguage');

params = {'GenerateHDLTestBench', 'on', ...
          'GenerateCosimModel', 'None', ...
          'GenerateCosimBlock', 'off'};
      
if strcmp(version('-release'),'2016a') % R2016a
    % Turn off no-reset ModelSim script as it's not compatible
    params = [params {'GenerateNoResetInitScript', 'off'}];
elseif ~verLessThan('matlab','9.3') % >= R2017b 
    % Set simulation tool to custom 
    params = [params {'SimulationTool', 'custom'}];
end

% Generate HDL for DUT and test bench
makehdl(dutPath, params{:}, params_isim{:});
makehdltb(dutPath, params{:}, params_isim{:});

% CD into HDL code gen dir to run the HDL simulation
if ~verLessThan('matlab','8.1')
    hdlDir = [targetDir filesep model];
else
    hdlDir = targetDir;
end
currentDir = pwd;
cd(hdlDir);

try
    % Generate ISIM/Vivado simulation executable (shell command)
    % e.g. fuse -prj symmetric_fir_tb_isim.prj work.symmetric_fir_tb
    % Other fuse options not used here include -o <name>.exe
    tbModuleName = [dut '_tb'];
    isimPrjName  = [tbModuleName isimPrjPostfix];
    isimTclName  = [tbModuleName isimTclPostfix];
    
    if strcmpi(targetLang, 'vhdl')
        simRes = ' -timeprecision_vhdl 1ns'; % Use 1ns resolution for VHDL
    else
        simRes = ''; % Verilog sim resolution is set by timescale
    end
       
    simCmd1 = [CompilerSelect simRes ' -prj ' isimPrjName ' work.' tbModuleName CompileCmdArg];    
    system(simCmd1);
    
    % Launch ISIM or Vivado simulator and run simulation (external shell command)
    % e.g. !x.exe -gui -tclbatch symmetric_fir_tb_isim.tcl &
  
    simCmd2 = [SimulatorSelect ' -gui -tclbatch ' isimTclName SimCmdArg ' &'];    
    system(simCmd2);
    
% Restore original pwd
catch me
    cd(currentDir);
    rethrow(me);
end

cd(currentDir);
