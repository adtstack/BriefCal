# Third-Party Notices

이 문서는 현재 KaosCal source dependency의 notice inventory다. KaosCal 자체의 license나
EULA를 정하지 않으며, 완전한 법률 검토 또는 최종 배포물에 notice가 포함됐다는 증거를
대체하지 않는다.

## 현재 SwiftPM inventory

2026-07-25의
`KaosCal.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`에는 다음
remote SwiftPM pin 두 개가 기록되어 있다.

| Component | Resolved version | Resolved revision | Upstream | License evidence |
| --- | --- | --- | --- | --- |
| GRDB.swift | 7.10.0 | `36e30a6f1ef10e4194f6af0cff90888526f0c115` | <https://github.com/groue/GRDB.swift> | Exact revision의 `LICENSE`: MIT License |
| Sparkle | 2.9.2 | `6276ba2b404829d139c45ff98427cf90e2efc59b` | <https://github.com/sparkle-project/Sparkle> | Exact revision의 `LICENSE`: Sparkle MIT License와 bundled external notices |

Exact revision license source:
<https://github.com/groue/GRDB.swift/blob/36e30a6f1ef10e4194f6af0cff90888526f0c115/LICENSE>

Sparkle exact revision license source:
<https://github.com/sparkle-project/Sparkle/blob/6276ba2b404829d139c45ff98427cf90e2efc59b/LICENSE>

### GRDB.swift — MIT License

```text
Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

### Sparkle — License and external notices

```text
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software
is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## 확인된 범위와 아직 필요한 확인

현재 저장소 근거로 확인할 수 있는 범위는 다음과 같다.

- `Package.resolved`가 GRDB.swift `7.10.0`, Sparkle `2.9.2`와 위 exact revision을 pin한다.
- 각 upstream exact revision의 `LICENSE`에는 위 copyright와 license/notice text가 있다.
- 현재 `Package.resolved`에는 이 둘 외의 remote SwiftPM pin이 없다.

이 사실만으로 아래 항목은 증명되지 않는다.

- 최종 compiled app/package에 포함된 모든 third-party code와 resource의 완전한 inventory
- package resolution이나 dependency update 뒤에도 version/revision/license가 같은지
- 이 Markdown notice가 최종 `.app`, ZIP/DMG 또는 사용자가 접근할 legal notice 위치에
  실제로 포함됐는지
- source, asset, build tool, copied snippet 등 SwiftPM 밖의 항목에 별도 license 의무가
  없는지
- KaosCal 자체 license/EULA와 third-party notice 표시 방식이 법적 요구를 충족하는지

따라서 외부 배포 전 release 담당자는 다음 gate를 모두 수행해야 한다.

1. release commit의 `Package.resolved`에서 version과 revision을 다시 확인한다.
2. pinned exact revision의 upstream license를 다시 내려받아 이 문서의 copyright와 전체
   license 내용을 대조하고, 최종 배포 notice에는 exact upstream text를 verbatim으로
   포함한다.
3. Xcode의 실제 resolved dependency graph와 최종 app payload를 조사해 새 direct/
   transitive dependency, vendored binary/resource가 없는지 확인한다.
4. SwiftPM 밖의 source, image, font, template, build artifact도 provenance와 license를
   별도로 점검한다.
5. 이 notice 또는 동일한 verbatim license를 최종 배포물에서 사용자가 접근할 위치에
   포함하고 clean package에서 존재를 검증한다.
6. dependency 변경 시 이 inventory와 [CHANGELOG.md](CHANGELOG.md)를 같은 change에서
   갱신한다.

현재 Xcode project에 이 Markdown을 app resource로 복사하는 명시적 build phase는 없다.
따라서 repository notice 작성은 완료됐지만 **최종 artifact bundling/license audit gate는
아직 pending**이다. 이 gate가 통과하기 전에는 `THIRD_PARTY_NOTICES.md`가 배포물에
포함됐다고 선언하지 않는다.

Apple SDK와 macOS system framework는 이 third-party inventory에 열거하지 않는다.
Developer Program, Xcode, Apple artwork/tooling의 별도 약관은 해당 계약에 따라 release
담당자가 확인한다.
