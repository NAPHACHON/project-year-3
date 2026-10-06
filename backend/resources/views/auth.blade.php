@extends('layout') @section('content')
<div class="auth-shell"><div class="auth-card"><div class="brand"><span class="brand-mark">⚡</span><div><b>CyberCafe Desk</b><small>ระบบบริหารจัดการร้านเกม</small></div></div><h1>{{ $register ? 'สร้างบัญชีสมาชิก' : 'เข้าสู่ระบบ' }}</h1><p class="muted">{{ $register ? 'สมัครสมาชิกเพื่อจองเครื่องและติดตามเวลาเล่น' : 'เข้าสู่ระบบเพื่อใช้งานร้านเกม' }}</p>
@if($errors->any())<div class="alert danger">{{ $errors->first() }}</div>@endif
<form method="post" action="{{ $register ? '/register' : '/login' }}">@csrf
@if($register)<label>ชื่อผู้ใช้<input name="name" value="{{ old('name') }}" required></label><label>เบอร์โทรศัพท์<input name="phone" value="{{ old('phone') }}" required></label>@endif
<label>อีเมล<input type="email" name="email" value="{{ old('email') }}" required></label><label>รหัสผ่าน<input type="password" name="password" required></label>@if($register)<label>ยืนยันรหัสผ่าน<input type="password" name="password_confirmation" required></label>@endif
<button class="primary full">{{ $register ? 'สมัครสมาชิก' : 'เข้าสู่ระบบ' }}</button></form>
<p class="switch">{{ $register ? 'มีบัญชีอยู่แล้ว?' : 'ยังไม่มีบัญชี?' }} <a href="{{ $register ? '/login' : '/register' }}">{{ $register ? 'เข้าสู่ระบบ' : 'สมัครสมาชิก' }}</a></p><div class="demo-note">บัญชีทดลอง: admin@cybercafe.test / AdminCafe!2026<br>สมาชิก: member@cybercafe.test / MemberCafe!2026</div></div></div>
@endsection
