# Wine 修補

重建 `patches/bin/` 內預先建置的 Wine DLL 與新增 Wine 修補；原始碼版本與 LGPL 資訊見 [patches/SOURCES.md](../patches/SOURCES.md)，各修補的原因見 [fixes.md](fixes.md)。

## 重建 DLL

```sh
just build-wine-dlls
(cd patches/bin/x86_64-windows && shasum -a 256 -- *) > patches/bin/SHA256SUMS
```

步驟、版本與需求見 `tools/dev/build-wine-dlls.sh` 開頭與各步驟註解。

## 新增修補

1. 在 `build/src/sources/wine` 修改。
2. 以 `diff -u` 產生 `a/`、`b/` 前綴的 patch 放進 `patches/`。
3. 在 `tools/dev/build-wine-dlls.sh` 的 `MODULES` 加入對應模組。
4. 更新 `patches/SOURCES.md`。`release.sh build` 會把其中第一個頂層 `- ` 清單（到下一個空行為止）原樣附進 release notes（LGPL 原始碼資訊），所以清單中間不能有空行，前面也不能有其他頂層清單；找不到清單時 `build` 中止。
5. 根因與證據寫進 [fixes.md](fixes.md)。
