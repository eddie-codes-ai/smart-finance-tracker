import site, os, sys

for path in site.getsitepackages():
    target = os.path.join(path, "frozendict", "__init__.py")
    if os.path.exists(target):
        with open(target, "r") as f:
            content = f.read()
        if "collections.Mapping" in content:
            content = content.replace("collections.Mapping", "collections.abc.Mapping")
            with open(target, "w") as f:
                f.write(content)
            print("frozendict patched successfully.")
        else:
            print("frozendict already patched.")
        break
```

**Step 3** — Update `Procfile` to run the patch first:
```
web: python patch_frozendict.py && gunicorn "app:create_app()"