# Countdown

The days left until a date, as a widget: "New Year, 46 days". On the day itself it says Today.

- **Shows**: a widget in the island's Widgets place.
- **Needs**: nothing but macOS.
- **Runs**: every hour.

Set the title and the date (`YYYY-MM-DD`) at the top of `countdown.sh`, then:

```sh
colctl extensions install examples/extensions/countdown --on
```

Install it twice under other names for several dates: `--name birthday`, `--name launch`.
