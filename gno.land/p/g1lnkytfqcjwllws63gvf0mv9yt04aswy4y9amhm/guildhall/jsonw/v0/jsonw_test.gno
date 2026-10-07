package jsonw

import (
	"testing"
	"time"

	"gno.land/p/nt/uassert/v0"
)

func TestString(t *testing.T) {
	uassert.Equal(t, `"plain"`, String("plain"))
	uassert.Equal(t, `"a\"b\\c"`, String(`a"b\c`))
	uassert.Equal(t, `"l1\nl2\tx\r"`, String("l1\nl2\tx\r"))
	uassert.Equal(t, `"\u0001\u001f\u007f"`, String("\x01\x1f\x7f"))
	uassert.Equal(t, `"\u2028"`, String("\u2028"))
	uassert.Equal(t, `"héllo 🛠"`, String("héllo 🛠"))
	uassert.Equal(t, `"a\ufffdb"`, String("a\xffb"))
}

func TestNumbers(t *testing.T) {
	uassert.Equal(t, "42", Int(42))
	uassert.Equal(t, "-7", Int(-7))
	uassert.Equal(t, `"9007199254740992"`, Int(9007199254740992))
	uassert.Equal(t, `"18446744073709551615"`, Uint(18446744073709551615))
	uassert.Equal(t, "true", Bool(true))
}

func TestCompose(t *testing.T) {
	got := Obj("id", Uint(3), "tags", Strings([]string{"a", "b"}), "none", Arr(nil), "at", Time(time.Time{}))
	uassert.Equal(t, `{"id":3,"tags":["a","b"],"none":[],"at":null}`, got)
	uassert.Equal(t, `"2026-10-07T12:00:00Z"`, Time(time.Date(2026, 10, 7, 12, 0, 0, 0, time.UTC)))
	uassert.Equal(t, `["g1x"]`, Addresses([]address{"g1x"}))
}
