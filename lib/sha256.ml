let pow2_32 = 4294967296 (* 2 ** 32 *)

let ( +| ) = Int32.add
let ( land ) = Int32.logand
let ( lor ) = Int32.logor
let ( lnot ) = Int32.lognot (* lnot is not an ocaml operator *)
let ( lxor ) = Int32.logxor
let ( lsr ) = Int32.shift_right_logical
let ( lsl ) = Int32.shift_left
let ( <<< ) a b = (a lsl b) lor (a lsr (32 - b)) (* rotate left *)
let ( >>> ) a b = (a lsr b) lor (a lsl (32 - b)) (* rotate right *)

let k64 =
  [|
    0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l; 0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
    0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l; 0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
    0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl; 0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
    0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l; 0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
    0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l; 0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
    0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l; 0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
    0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l; 0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
    0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l; 0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l
  |]



let ch x y z = (x land y) lor ((lnot x) land z)

let maj x y z = (x land y) lxor (x land z) lxor (y land z)

let sigma_maj0 x = (x >>> 2) lxor (x >>> 13) lxor (x >>> 22)
let sigma_maj1 x = (x >>> 6) lxor (x >>> 11) lxor (x >>> 25)
let sigma_min0 x = (x >>> 7) lxor (x >>> 18) lxor (x lsr 3)
let sigma_min1 x = (x >>> 17) lxor (x >>> 19) lxor (x lsr 10)

let bitstring_of_int64 n =
  let buff = Bytes.create 8 in
  let ( lsr ) = Int64.shift_right_logical in
  let ( land ) = Int64.logand in
  let extract i =
    buff.[i] <- char_of_int (Int64.to_int ((n lsr ((7 - i) * 8)) land 0xFFL))
  in
  extract 7;
  extract 6;
  extract 5;
  extract 4;
  extract 3;
  extract 2;
  extract 1;
  extract 0;
  buff

let padding m =
  let size = Bytes.length m in
  let extsize =
    if (size mod 64) * 8 >= 448 then 128 - size mod 64
    else 64 - size mod 64
  in
  let m = Bytes.extend m 0 extsize in
  m.[size] <- '\x80';
  for i = size + 1 to Bytes.length m - 9 do
    m.[i] <- '\x00'
  done;
  Bytes.blit
    (bitstring_of_int64 (Int64.of_int (size * 8))) 0 m (Bytes.length m - 8) 8;
  m

let hash512 array h0 h1 h2 h3 h4 h5 h6 h7 msg =
  let init16 () =
    for i = 0 to 15 do
      (Int32.of_int (Char.code msg.[i * 4 + 3])) lor
      ((Int32.of_int (Char.code msg.[i * 4 + 2])) lsl 8) lor
      ((Int32.of_int (Char.code msg.[i * 4 + 1])) lsl 16) lor
      ((Int32.of_int (Char.code msg.[i * 4])) lsl 24)
      |> Array.set array i
    done
  in
  let genwords () =
    for t = 16 to 63 do
      array.(t) <-
	sigma_min1 array.(t - 2)
	+| array.(t - 7) +| sigma_min0 array.(t - 15)
	+| array.(t - 16)
    done
  in
  let a = ref !h0 in
  let b = ref !h1 in
  let c = ref !h2 in
  let d = ref !h3 in
  let e = ref !h4 in
  let f = ref !h5 in
  let g = ref !h6 in
  let h = ref !h7 in
  let r1 = ref 0l in
  let r2 = ref 0l in
  let loop () =
    for t = 0 to 63 do
      r1 := !h +| sigma_maj1 !e +| ch !e !f !g +| k64.(t)
	    +| array.(t);
      r2 := sigma_maj0 !a +| maj !a !b !c;
      h := !g;
      g := !f;
      f := !e;
      e := !d +| !r1;
      d := !c;
      c := !b;
      b := !a;
      a := !r1 +| !r2;
    done
  in
  init16 ();
  genwords ();
  loop ();
  h0 := !a +| !h0;
  h1 := !b +| !h1;
  h2 := !c +| !h2;
  h3 := !d +| !h3;
  h4 := !e +| !h4;
  h5 := !f +| !h5;
  h6 := !g +| !h6;
  h7 := !h +| !h7

let encrypt s =
  let bitstringify b i n =
    let extract_byte k =
      char_of_int (Int32.to_int ((n lsr (k * 8)) land 0xFFl))
    in
    b.[i]     <- extract_byte 3;
    b.[i + 1] <- extract_byte 2;
    b.[i + 2] <- extract_byte 1;
    b.[i + 3] <- extract_byte 0
  in
  let m = padding (Bytes.of_string s) in
  let w = Array.make 128 0l in
  let h0 = ref 0x6A09E667l in
  let h1 = ref 0xBB67AE85l in
  let h2 = ref 0x3C6EF372l in
  let h3 = ref 0xA54FF53Al in
  let h4 = ref 0x510E527Fl in
  let h5 = ref 0x9B05688Cl in
  let h6 = ref 0x1F83D9ABl in
  let h7 = ref 0x5BE0CD19l in
  for i = 0 to Bytes.length m / 64 - 1 do
    hash512 w h0 h1 h2 h3 h4 h5 h6 h7 (Bytes.sub m (i * 64) 64);
    Array.fill w 0 128 0l
  done;
  let h = Bytes.create 32 in
  bitstringify h 0 !h0;
  bitstringify h 4 !h1;
  bitstringify h 8 !h2;
  bitstringify h 12 !h3;
  bitstringify h 16 !h4;
  bitstringify h 20 !h5;
  bitstringify h 24 !h6;
  bitstringify h 28 !h7;
  Bytes.to_string h

module Utils = struct
  let sha256_to_hexstring ?(case=`Lower) s =
    if String.length s <> 32 then invalid_arg "Sha-256 digest expected."
    else
      let sprint = match case with
	| `Lower -> Printf.sprintf "%08lx%08lx%08lx%08lx%08lx%08lx%08lx%08lx"
	| `Upper -> Printf.sprintf "%08lX%08lX%08lX%08lX%08lX%08lX%08lX%08lX"
      in
      let extract_int32 i =
	let b1 = int_of_char s.[i] in
	let b2 = int_of_char s.[i + 1] in
	let b3 = int_of_char s.[i + 2] in
	let b4 = int_of_char s.[i + 3] in
	Int32.of_int
          Pervasives.(((b1 land 0xFF) lsl 24) lor (((b2 land 0xFF) lsl 16))
                      lor (((b3 land 0xFF) lsl 8)) lor (b4 land 0xFF))
      in
      let n1 = extract_int32 0 in
      let n2 = extract_int32 4 in
      let n3 = extract_int32 8 in
      let n4 = extract_int32 12 in
      let n5 = extract_int32 16 in
      let n6 = extract_int32 20 in
      let n7 = extract_int32 24 in
      let n8 = extract_int32 28 in
      sprint n1 n2 n3 n4 n5 n6 n7 n8
end