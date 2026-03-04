#!/usr/bin/env python3

import os
import sys
import subprocess

def do_dir(dir_name):
  os.makedirs(dir_name+"_result", exist_ok=True)
  param = ['python', 'combine_hints.py', 'diff', '3', os.path.join(dir_name+"_result", 'merged.profile')]
  for dirpath, dirnames, filenames in os.walk(dir_name):
    for filename in filenames:
      file_path = os.path.join(dirpath, filename)
      old_content = []
      with open(file_path, 'r', encoding='utf-8') as f:
        old_content = f.readlines()
      new_content = [c for c in old_content if len(c.strip().split('\t')) == 4]
      with open(file_path, 'w', encoding='utf-8') as f:
        f.writelines(new_content)
      in_param = ['python', 'get_hints.py', '--min', '100', '--ratio', '40', file_path, os.path.join(dir_name + '_result', filename)]
      print(in_param)
      result = subprocess.run(in_param, capture_output=True, text=True)
      if result.stderr:
        print("get_hints", file_path, '错误输出')
        print(result.stderr)
        raise Exception('s')
      param.append(os.path.join(dir_name+"_result", filename))
      param.append('1')
  print(param)
  result = subprocess.run(param, capture_output=True, text=True)
  if result.stderr:
    print("combine_hints 错误输出")
    print(result.stderr)
    raise Exception('g')

do_dir('ios')
do_dir('android')



