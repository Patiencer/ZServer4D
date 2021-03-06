unit CommunicationFramework_Client_CrossSocket;

interface

uses SysUtils, Classes,
  Net.CrossSocket, Net.SocketAPI, Net.CrossSocket.Base,
  CommunicationFramework_Server_CrossSocket,
  CommunicationFramework, CoreClasses, UnicodeMixedLib, MemoryStream64;

type
  TContextIntfForClient = TContextIntfForServer;

  TCommunicationFramework_Client_CrossSocket = class(TCommunicationFrameworkClient)
  private
    FDriver     : TDriverEngine;
    ClientIOIntf: TContextIntfForClient;

    procedure DoConnected(Sender: TObject; AConnection: ICrossConnection); virtual;
    procedure DoDisconnect(Sender: TObject; AConnection: ICrossConnection); virtual;
    procedure DoReceived(Sender: TObject; AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
    procedure DoSent(Sender: TObject; AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer); virtual;
  public
    constructor Create;
    destructor Destroy; override;

    function Connected: Boolean; override;
    function ClientIO: TPeerClient; override;
    procedure TriggerQueueData(v: PQueueData); override;
    procedure ProgressBackground; override;

    function Connect(host: string; Port: Word): Boolean; overload;
    function Connect(host: string; Port: string): Boolean; overload;
    procedure Disconnect;

    property Driver: TDriverEngine read FDriver;
  end;

implementation

procedure TCommunicationFramework_Client_CrossSocket.DoConnected(Sender: TObject; AConnection: ICrossConnection);
var
  cli: TContextIntfForClient;
begin
  TThread.Synchronize(nil,
    procedure
    begin
      cli := TContextIntfForClient.Create(Self, AConnection.ConnectionIntf);
      cli.LastActiveTime := GetTimeTickCount;
      AConnection.UserObject := cli;

      ClientIOIntf := cli;

      inherited DoConnected(cli);
    end);
end;

procedure TCommunicationFramework_Client_CrossSocket.DoDisconnect(Sender: TObject; AConnection: ICrossConnection);
var
  cli: TContextIntfForClient;
begin
  TThread.Synchronize(nil,
    procedure
    begin
      cli := AConnection.UserObject as TContextIntfForClient;
      if cli = nil then
          exit;

      cli.ClientIntf := nil;
      AConnection.UserObject := nil;
      inherited DoDisconnect(cli);
    end);
end;

procedure TCommunicationFramework_Client_CrossSocket.DoReceived(Sender: TObject; AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer);
var
  cli: TContextIntfForClient;
begin
  cli := AConnection.UserObject as TContextIntfForClient;
  if cli = nil then
      exit;

  if (cli.ClientIntf = nil) then
      exit;

  while cli.AllSendProcessing do
      TThread.Sleep(1);

  TThread.Synchronize(nil,
    procedure
    begin
      try
        cli.LastActiveTime := GetTimeTickCount;
        cli.ReceivedBuffer.Position := cli.ReceivedBuffer.size;
        cli.ReceivedBuffer.Write(ABuf^, ALen);
        // cli.FillRecvBuffer(nil, False, False);
      except
      end;
    end);
end;

procedure TCommunicationFramework_Client_CrossSocket.DoSent(Sender: TObject; AConnection: ICrossConnection; ABuf: Pointer; ALen: Integer);
var
  cli: TContextIntfForClient;
begin
  cli := AConnection.UserObject as TContextIntfForClient;
  if cli = nil then
      exit;

  if (cli.ClientIntf = nil) then
      exit;

  cli.LastActiveTime := GetTimeTickCount;
end;

constructor TCommunicationFramework_Client_CrossSocket.Create;
var
  r: TCommandStreamMode;
begin
  inherited Create;
  FDriver := TDriverEngine.Create(1);
  FDriver.OnConnected := DoConnected;
  FDriver.OnDisconnected := DoDisconnect;
  FDriver.OnReceived := DoReceived;
  FDriver.OnSent := DoSent;
end;

destructor TCommunicationFramework_Client_CrossSocket.Destroy;
begin
  Disconnect;
  // try
  // DisposeObject(FDriver);
  // except
  // end;
  inherited Destroy;
end;

function TCommunicationFramework_Client_CrossSocket.Connected: Boolean;
begin
  Result := (ClientIO <> nil) and (ClientIO.Connected);
end;

function TCommunicationFramework_Client_CrossSocket.ClientIO: TPeerClient;
begin
  Result := ClientIOIntf;
end;

procedure TCommunicationFramework_Client_CrossSocket.TriggerQueueData(v: PQueueData);
begin
  (*
    TThread.Synchronize(nil,
    procedure
    begin
    end);
  *)

  if not Connected then
    begin
      DisposeQueueData(v);
      exit;
    end;

  ClientIOIntf.PostQueueData(v);
  ClientIOIntf.FillRecvBuffer(nil, False, False);
end;

procedure TCommunicationFramework_Client_CrossSocket.ProgressBackground;
var
  i: Integer;
begin
  if not Connected then
    begin
      if ClientIOIntf <> nil then
        begin
          DisposeObject(ClientIOIntf);
          ClientIOIntf := nil;
        end;
    end;

  try
    if (IdleTimeout > 0) and (GetTimeTickCount - ClientIOIntf.LastActiveTime > IdleTimeout) then
        Disconnect;
  except
  end;

  try
    if ClientIOIntf <> nil then
        ClientIOIntf.FillRecvBuffer(nil, False, False);
    if ClientIOIntf <> nil then
        ClientIOIntf.ProcessAllSendCmd(nil, False, False);
  except
  end;

  inherited ProgressBackground;

  CheckSynchronize;
end;

function TCommunicationFramework_Client_CrossSocket.Connect(host: string; Port: Word): Boolean;
var
  completed, r: Boolean;
begin
  completed := False;
  r := False;
  ICrossSocket(FDriver).Connect(host, Port,
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    begin
      completed := True;
      r := ASuccess;
      // if ASuccess then
      // ClientIO.Print('Connect %s:%d success!', [host, Port])
      // else
      // ClientIO.Print('Connect %s:%d failed!', [host, Port]);
      (*
        TThread.Synchronize(nil,
        procedure
        begin
        end);
      *)
    end);

  while not completed do
      CheckSynchronize(5);
  Result := r;
end;

function TCommunicationFramework_Client_CrossSocket.Connect(host: string; Port: string): Boolean;
begin
  Result := Connect(host, umlStrToInt(Port, 0));
end;

procedure TCommunicationFramework_Client_CrossSocket.Disconnect;
begin
  if Connected then
      ClientIO.Disconnect;
end;

initialization

finalization

end.
