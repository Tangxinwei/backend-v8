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

if(process.argv[3] == 'true'){
    v8_h_insert_code = v8_h_insert_code + `
#define PUERTS_V8_USE_CUSTOM_CXX 1
#inlcude "v8-inspector.h"
#include "libplatform/libplatform.h"
namespace v8
{
V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<ArrayBuffer> array_buffer);
V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<SharedArrayBuffer> array_buffer);
V8_EXPORT void PuertsReleaseBackingStore(int Index);

namespace platform {
V8_EXPORT int Wrapper_NewDefaultPlatform(int thread_pool_size = 0,
    IdleTaskSupport idle_task_support = IdleTaskSupport::kDisabled,
    InProcessStackDumping in_process_stack_dumping =
        InProcessStackDumping::kDisabled,
    PriorityMode priority_mode = PriorityMode::kDontApply);
V8_EXPORT void PuertsReleasePlatform(int Index);
}

V8_EXPORT int Wrapper_Inspector_Create(Isolate*, V8InspectorClient*);
V8_EXPORT void PuertsReleaseInspector(int Index);
}
    `
}


fs.writeFileSync(v8_h_path, v8_h_context.slice(0, v8_h_insert_pos) + v8_h_insert_code + v8_h_context.slice(v8_h_insert_pos));


let api_cc_path = process.argv[2] + '/src/api/api.cc';

let api_cc_insert_code = `
#include "include/v8-version.h"
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

if(process.argv[3] == 'true')
{
    api_cc_insert_code = api_cc_insert_code + `
namespace v8
{
static std::vector<std::shared_ptr<BackingStore> > _cached_backing_store;
static std::vector<int> free_cached_backing_store_list;
V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<ArrayBuffer> array_buffer)
{
  std::shared_ptr<BackingStore> bs = array_buffer->GetBackingStore();
  if(free_cached_backing_store_list.size())
  {
    int ret = free_cached_backing_store_list.back();
    free_cached_backing_store_list.pop_back();
    _cached_backing_store[ret] = bs;
    return ret;
  }
  _cached_backing_store.push_back(bs);
  return _cached_backing_store.size() - 1;
}

V8_EXPORT int ArrayBuffer_KeepBackingStore(Local<SharedArrayBuffer> array_buffer)
{
  std::shared_ptr<BackingStore> bs = array_buffer->GetBackingStore();
  if(free_cached_backing_store_list.size())
  {
    int ret = free_cached_backing_store_list.back();
    free_cached_backing_store_list.pop_back();
    _cached_backing_store[ret] = bs;
    return ret;
  }
  _cached_backing_store.push_back(bs);
  return _cached_backing_store.size() - 1;
}

V8_EXPORT void PuertsReleaseBackingStore(int Index)
{
  _cached_backing_store[Index].reset();
  free_cached_backing_store_list.push_back(Index);
}

namespace platform {
static std::vector<std::unique_ptr<v8::Platform> > _cached_platform;
static std::vector<int> free_cached_platform;
V8_EXPORT int Wrapper_NewDefaultPlatform(int thread_pool_size, IdleTaskSupport idle_task_support, InProcessStackDumping in_process_stack_dumping,PriorityMode priority_mode)
{
  std::unique_ptr<v8::Platform> p = NewDefaultPlatform(thread_pool_size, idle_task_support, in_process_stack_dumping, priority_mode);
  if(free_cached_platform.size())
  {
    int ret = free_cached_platform.back();
    free_cached_platform.pop_back();
    _cached_platform[ret] = std::move(p);
    return ret;
  }
  _cached_platform.push_back(std::move(p));
  return _cached_platform.size() - 1;
}

V8_EXPORT void PuertsReleasePlatform(int Index)
{
  _cached_platform[Index].reset();
  free_cached_platform.push_back(Index);
}

}

static std::vector<std::unique_ptr<V8Inspector> > _cached_inspector;
static std::vector<int> free_cached_inspector;
V8_EXPORT int Wrapper_Inspector_Create(Isolate* Isolate, V8InspectorClient* Client)
{
  std::unique_ptr<V8Inspector> s = V8Inspector::create(Isolate, Client);
  if(free_cached_inspector.size())
  {
    int ret = free_cached_inspector.back();
    free_cached_inspector.pop_back();
    _cached_inspector[ret] = std::move(s);
    return ret;
  }
  _cached_inspector.push_back(std::move(s));
  return _cached_inspector.size() - 1;
}

V8_EXPORT void PuertsReleaseInspector(int Index)
{
  _cached_inspector[Index].reset();
  free_cached_inspector.push_back(Index);
}
}
    `
}

fs.writeFileSync(api_cc_path, fs.readFileSync(api_cc_path, 'utf-8') + api_cc_insert_code);