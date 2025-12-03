const fs = require('fs');

let v8_h_path = process.argv[2] + '/include/v8.h';

let v8_h_context = fs.readFileSync(v8_h_path, 'utf-8');

let v8_h_insert_pos = v8_h_context.lastIndexOf('#endif');

let v8_h_insert_code = `

#define HAS_ARRAYBUFFER_NEW_WITHOUT_STL 1

namespace v8
{
// do not new two ArrayBuffer with the same data and length
V8_EXPORT Local<ArrayBuffer> ArrayBuffer_New_Without_Stl(Isolate* isolate, 
      void* data, size_t byte_length, v8::BackingStore::DeleterCallback deleter,
      void* deleter_data);
V8_EXPORT Local<ArrayBuffer> ArrayBuffer_New_Without_Stl(Isolate* isolate, 
      void* data, size_t byte_length);
V8_EXPORT void* ArrayBuffer_Get_Data(Local<ArrayBuffer> array_buffer, size_t &byte_length);
V8_EXPORT void* ArrayBuffer_Get_Data(Local<ArrayBuffer> array_buffer);
}

`;


    v8_h_insert_code = v8_h_insert_code + `
#if defined(V8_OS_WIN) && V8_OS_WIN
#define PUERTS_V8_USE_CUSTOM_CXX 1
#else
#define PUERTS_V8_USE_CUSTOM_CXX 0
#endif
#if PUERTS_V8_USE_CUSTOM_CXX
#include "v8-inspector.h"
#include "libplatform/libplatform.h"
namespace v8
{
V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<ArrayBuffer> array_buffer);
V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<SharedArrayBuffer> array_buffer);
V8_EXPORT v8::BackingStore* PuertsGetBackingStore(int Index);
V8_EXPORT void PuertsReleaseBackingStore(int Index);

namespace platform {
V8_EXPORT int Wrapper_NewDefaultPlatform(int thread_pool_size = 0,
    IdleTaskSupport idle_task_support = IdleTaskSupport::kDisabled,
    InProcessStackDumping in_process_stack_dumping =
        InProcessStackDumping::kDisabled,
    PriorityMode priority_mode = PriorityMode::kDontApply);
V8_EXPORT v8::Platform* PuertsGetPlatform(int Index);
V8_EXPORT void PuertsReleasePlatform(int Index);
}

V8_EXPORT int Wrapper_Inspector_Create(Isolate*, v8_inspector::V8InspectorClient*);
V8_EXPORT v8_inspector::V8Inspector* PuertsGetInspector(int Index);
V8_EXPORT void PuertsReleaseInspector(int Index);

V8_EXPORT int Wrapper_Inspector_Connect(v8_inspector::V8Inspector* inspector, int contextGroupId, v8_inspector::V8Inspector::Channel channel, \
                        v8_inspector::StringView str_view, v8_inspector::V8Inspector::ClientTrustLevel client_trust_level, v8_inspector::V8Inspector::SessionPauseState session_pause_state);
V8_EXPORT v8_inspector::V8InspectorSession* PuertsGetV8InspectorSession(int Index);
V8_EXPORT void PuertsReleaseInspectorSession(int Index);
}
#endif
    `



fs.writeFileSync(v8_h_path, v8_h_context.slice(0, v8_h_insert_pos) + v8_h_insert_code + v8_h_context.slice(v8_h_insert_pos));


let api_cc_path = process.argv[2] + '/src/api/api.cc';

let api_cc_insert_code = `
#include "include/v8.h"
namespace v8
{
V8_EXPORT Local<ArrayBuffer> ArrayBuffer_New_Without_Stl(Isolate* isolate, 
      void* data, size_t byte_length, BackingStore::DeleterCallback deleter,
      void* deleter_data)
{
    auto Backing = ArrayBuffer::NewBackingStore(
            data, byte_length,deleter,
            deleter_data);
    return ArrayBuffer::New(isolate, std::move(Backing));
}

V8_EXPORT Local<ArrayBuffer> ArrayBuffer_New_Without_Stl(Isolate* isolate, 
      void* data, size_t byte_length)
{
#if V8_MAJOR_VERSION < 9
  CHECK_IMPLIES(byte_length != 0, data != nullptr);
  CHECK_LE(byte_length, i::JSArrayBuffer::kMaxByteLength);
  i::Isolate* i_isolate = reinterpret_cast<i::Isolate*>(isolate);

  std::shared_ptr<i::BackingStore> backing_store = LookupOrCreateBackingStore(
      i_isolate, data, byte_length, i::SharedFlag::kNotShared, ArrayBufferCreationMode::kExternalized);

  i::Handle<i::JSArrayBuffer> obj =
      i_isolate->factory()->NewJSArrayBuffer(std::move(backing_store));
  obj->set_is_external(true);
  return Utils::ToLocal(obj);
#else
  auto Backing = ArrayBuffer::NewBackingStore(
          data, byte_length, BackingStore::EmptyDeleter, nullptr);
  return ArrayBuffer::New(isolate, std::move(Backing));
#endif
}

V8_EXPORT void* ArrayBuffer_Get_Data(Local<ArrayBuffer> array_buffer, size_t &byte_length)
{
    byte_length = array_buffer->GetBackingStore()->ByteLength();
    return array_buffer->GetBackingStore()->Data();
}
V8_EXPORT void* ArrayBuffer_Get_Data(Local<ArrayBuffer> array_buffer)
{
    return array_buffer->GetBackingStore()->Data();
}

}
`


api_cc_insert_code = api_cc_insert_code + `
#if  PUERTS_V8_USE_CUSTOM_CXX
namespace v8
{
static std::vector<std::shared_ptr<BackingStore> >* _cached_backing_store = nullptr;
static std::vector<int>* free_cached_backing_store_list = nullptr;
V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<ArrayBuffer> array_buffer)
{
  if(!_cached_backing_store)
  {
    _cached_backing_store = new std::vector<std::shared_ptr<BackingStore> >();
    free_cached_backing_store_list = new std::vector<int>();
  }
  std::shared_ptr<BackingStore> bs = array_buffer->GetBackingStore();
  if(free_cached_backing_store_list->size())
  {
    int ret = free_cached_backing_store_list->back();
    free_cached_backing_store_list->pop_back();
    (*_cached_backing_store)[ret] = bs;
    return ret;
  }
  _cached_backing_store->push_back(bs);
  return (int)_cached_backing_store->size() - 1;
}

V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<SharedArrayBuffer> array_buffer)
{
  if(!_cached_backing_store)
  {
    _cached_backing_store = new std::vector<std::shared_ptr<BackingStore> >();
    free_cached_backing_store_list = new std::vector<int>();
  }
  std::shared_ptr<BackingStore> bs = array_buffer->GetBackingStore();
  if(free_cached_backing_store_list->size())
  {
    int ret = free_cached_backing_store_list->back();
    free_cached_backing_store_list->pop_back();
    (*_cached_backing_store)[ret] = bs;
    return ret;
  }
  _cached_backing_store->push_back(bs);
  return (int)_cached_backing_store->size() - 1;
}

V8_EXPORT v8::BackingStore* PuertsGetBackingStore(int Index)
{
  return (*_cached_backing_store)[Index].get();
}

V8_EXPORT void PuertsReleaseBackingStore(int Index)
{
  (*_cached_backing_store)[Index].reset();
  free_cached_backing_store_list->push_back(Index);
}

namespace platform {
static std::vector<std::unique_ptr<v8::Platform> >* _cached_platform = nullptr;
static std::vector<int>* free_cached_platform = nullptr;
V8_EXPORT int Wrapper_NewDefaultPlatform(int thread_pool_size, IdleTaskSupport idle_task_support, InProcessStackDumping in_process_stack_dumping,PriorityMode priority_mode)
{
  if(!_cached_platform)
  {
    _cached_platform = new std::vector<std::unique_ptr<v8::Platform> >();
    free_cached_platform = new std::vector<int>();
  }
  std::unique_ptr<v8::Platform> p = NewDefaultPlatform(thread_pool_size, idle_task_support, in_process_stack_dumping, nullptr, priority_mode);
  if(free_cached_platform->size())
  {
    int ret = free_cached_platform->back();
    free_cached_platform->pop_back();
    (*_cached_platform)[ret] = std::move(p);
    return ret;
  }
  _cached_platform->push_back(std::move(p));
  return (int)_cached_platform->size() - 1;
}

V8_EXPORT v8::Platform* PuertsGetPlatform(int Index)
{
  return (*_cached_platform)[Index].get();
}

V8_EXPORT void PuertsReleasePlatform(int Index)
{
  (*_cached_platform)[Index].reset();
  free_cached_platform->push_back(Index);
}

}

static std::vector<std::unique_ptr<v8_inspector::V8Inspector> >* _cached_inspector = nullptr;
static std::vector<int>* free_cached_inspector = nullptr;
V8_EXPORT int Wrapper_Inspector_Create(Isolate* Isolate, v8_inspector::V8InspectorClient* Client)
{
  if(!_cached_inspector)
  {
    _cached_inspector = new std::vector<std::unique_ptr<v8_inspector::V8Inspector> >();
    free_cached_inspector = new std::vector<int>();
  }
  std::unique_ptr<v8_inspector::V8Inspector> s = v8_inspector::V8Inspector::create(Isolate, Client);
  if(free_cached_inspector->size())
  {
    int ret = free_cached_inspector->back();
    free_cached_inspector->pop_back();
    (*_cached_inspector)[ret] = std::move(s);
    return ret;
  }
  _cached_inspector->push_back(std::move(s));
  return (int)_cached_inspector->size() - 1;
}

V8_EXPORT v8_inspector::V8Inspector* PuertsGetInspector(int Index)
{
  return (*_cached_inspector)[Index].get();
}

V8_EXPORT void PuertsReleaseInspector(int Index)
{
  (*_cached_inspector)[Index].reset();
  free_cached_inspector->push_back(Index);
}

static std::vector<std::unique_ptr<v8_inspector::V8InspectorSession> >* _cached_inspector_session = nullptr;
static std::vector<int>* free_cached_inspector_session = nullptr;
V8_EXPORT int Wrapper_Inspector_Connect(v8_inspector::V8Inspector* inspector, int contextGroupId, v8_inspector::V8Inspector::Channel channel, \
                        v8_inspector::StringView str_view, v8_inspector::V8Inspector::ClientTrustLevel client_trust_level, v8_inspector::V8Inspector::SessionPauseState session_pause_state)
{
  if(!_cached_inspector_session)
  {
    _cached_inspector_session = new std::vector<std::unique_ptr<v8_inspector::V8InspectorSession> >();
    free_cached_inspector_session = new std::vector<int>();
  }
  std::unique_ptr<v8_inspector::V8InspectorSession> s = inspector->connect(contextGroupId, channel, str_view, client_trust_level, session_pause_state);
  if(free_cached_inspector_session->size())
  {
    int ret = free_cached_inspector_session->back();
    free_cached_inspector_session->pop_back();
    (*_cached_inspector_session)[ret] = std::move(s);
    return ret;
  }
  _cached_inspector_session->push_back(std::move(s));
  return (int)_cached_inspector_session->size() - 1;
}

V8_EXPORT v8_inspector::V8InspectorSession* PuertsGetV8InspectorSession(int Index)
{
  return (*_cached_inspector_session)[Index].get();
}

V8_EXPORT void PuertsReleaseInspectorSession(int Index)
{
  (*_cached_inspector_session)[Index].reset();
  free_cached_inspector_session->push_back(Index);
}

}
#endif
    `

fs.writeFileSync(api_cc_path, fs.readFileSync(api_cc_path, 'utf-8') + api_cc_insert_code);