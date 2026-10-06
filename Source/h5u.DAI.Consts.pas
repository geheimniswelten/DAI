unit h5u.DAI.Consts;

interface

const
  {$IFDEF WIN64}
  CDAIIDEArchitecture = 'Win64';
  CDAIKnownPackagesKey = 'Known Packages x64';
  {$ELSE}
  CDAIIDEArchitecture = 'Win32';
  CDAIKnownPackagesKey = 'Known Packages';
  {$ENDIF}
  CDAIName = 'DAI';
  CDAIDisplayName = 'Delphi AI';
  CDAIVersion = '1.2.21';
  CDAIDefaultPort = 7331;
  CDAIDefaultBindAddress = '127.0.0.1';
  CDAIMcpPath = '/mcp';
  CDAIRegistrySubKey = 'DAI';
  CDAICodexServerName = 'dai';
  CDAIManagedBlockBegin = '# >>> DAI managed >>>';
  CDAIManagedBlockEnd = '# <<< DAI managed <<<';
  CDAISkillDirectoryName = 'dai-delphi-ide';
  CDAILegacySkillDirectoryName = 'delphi-ide';
  CDAIMaxRequestBytes = 32 * 1024 * 1024;
  CDAIMaxTextFileBytes = 16 * 1024 * 1024;
  CDAIDefaultProcessTimeoutMs = 300000;
  CDAIMaxProcessOutputBytes = 8 * 1024 * 1024;

implementation

end.
