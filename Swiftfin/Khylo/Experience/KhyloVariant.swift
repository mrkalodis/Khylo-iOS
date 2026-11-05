//
// Khylo is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Khylo & Khylo Contributors
//

/// Which app this build is: the full Khylo app, or Khylo Music (built with the
/// `KHYLO_MUSIC` setting), which is the same code with only music in it.
enum KhyloVariant {

    static let isMusic: Bool = {
        #if KHYLO_MUSIC
        true
        #else
        false
        #endif
    }()
}
