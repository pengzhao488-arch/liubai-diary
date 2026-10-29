#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winhttp.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <cstdint>

struct LiubaiResponse {
  int32_t status;
  uint32_t length;
  uint32_t error;
  unsigned char* body;
};
struct InternetHandle {
  HINTERNET h;
  explicit InternetHandle(HINTERNET value) : h(value) {}
  ~InternetHandle() { if(h) WinHttpCloseHandle(h); }
};
extern "C" __declspec(dllexport) void liubai_free(LiubaiResponse* r) {
  if(r) { std::free(r->body); std::free(r); }
}
extern "C" __declspec(dllexport) LiubaiResponse* liubai_request(
    const wchar_t* url, const wchar_t* method, const wchar_t* headers,
    const unsigned char* body, uint32_t length) {
  auto* response = static_cast<LiubaiResponse*>(std::calloc(1,sizeof(LiubaiResponse)));
  if(!response) return nullptr;
  auto fail = [&]() { response->error=GetLastError(); return response; };
  URL_COMPONENTS parts{}; parts.dwStructSize=sizeof(parts);
  parts.dwSchemeLength=parts.dwHostNameLength=parts.dwUrlPathLength=parts.dwExtraInfoLength=static_cast<DWORD>(-1);
  if(!WinHttpCrackUrl(url,0,0,&parts)) return fail();
  if(parts.nScheme!=INTERNET_SCHEME_HTTPS) { response->error=ERROR_INVALID_PARAMETER; return response; }
  std::wstring host(parts.lpszHostName,parts.dwHostNameLength);
  std::wstring path(parts.lpszUrlPath,parts.dwUrlPathLength);
  if(path.empty()) path=L"/";
  if(parts.dwExtraInfoLength) path.append(parts.lpszExtraInfo,parts.dwExtraInfoLength);
  InternetHandle session(WinHttpOpen(L"LiubaiDiary/0.1.2",WINHTTP_ACCESS_TYPE_NO_PROXY,
    WINHTTP_NO_PROXY_NAME,WINHTTP_NO_PROXY_BYPASS,0));
  if(!session.h) return fail();
  WinHttpSetTimeouts(session.h,10000,15000,20000,20000);
#ifdef WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL
  DWORD protocols=WINHTTP_PROTOCOL_FLAG_HTTP2;
  WinHttpSetOption(session.h,WINHTTP_OPTION_ENABLE_HTTP_PROTOCOL,&protocols,sizeof(protocols));
#endif
  InternetHandle connection(WinHttpConnect(session.h,host.c_str(),parts.nPort,0));
  if(!connection.h) return fail();
  InternetHandle request(WinHttpOpenRequest(connection.h,method,path.c_str(),nullptr,
    WINHTTP_NO_REFERER,WINHTTP_DEFAULT_ACCEPT_TYPES,WINHTTP_FLAG_SECURE));
  if(!request.h) return fail();
  DWORD redirectPolicy=WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
  if(!WinHttpSetOption(request.h,WINHTTP_OPTION_REDIRECT_POLICY,&redirectPolicy,sizeof(redirectPolicy))) return fail();
  // No security-ignore flags: Schannel validates the server and certificates.
  if(!WinHttpSendRequest(request.h,headers,static_cast<DWORD>(-1),
      length?const_cast<unsigned char*>(body):WINHTTP_NO_REQUEST_DATA,length,length,0)) return fail();
  if(!WinHttpReceiveResponse(request.h,nullptr)) return fail();
  DWORD status=0,size=sizeof(status);
  if(!WinHttpQueryHeaders(request.h,WINHTTP_QUERY_STATUS_CODE|WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX,&status,&size,WINHTTP_NO_HEADER_INDEX)) return fail();
  response->status=static_cast<int32_t>(status);
  std::vector<unsigned char> buffer;
  unsigned char chunk[16384];
  while(true) {
    DWORD count=0;
    if(!WinHttpReadData(request.h,chunk,sizeof(chunk),&count)) return fail();
    if(!count) break;
    if(buffer.size()+count>32*1024*1024) { response->error=ERROR_INSUFFICIENT_BUFFER; return response; }
    buffer.insert(buffer.end(),chunk,chunk+count);
  }
  response->length=static_cast<uint32_t>(buffer.size());
  if(!buffer.empty()) {
    response->body=static_cast<unsigned char*>(std::malloc(buffer.size()));
    if(!response->body) { response->error=ERROR_NOT_ENOUGH_MEMORY; return response; }
    std::memcpy(response->body,buffer.data(),buffer.size());
  }
  return response;
}
