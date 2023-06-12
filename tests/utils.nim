proc cStringToString*(arr: openArray[char]): string =
    for c in items(arr):
        if c != '\0':
            result = result & c