# 即時行程板

登記你預計幾點抵達某個地點、用什麼交通方式，即時聚合成每 15 分鐘的人數分布。

這是「如果每個人的行程都是即時的」這個想法的第一個小工具。重點不在收集行程，而在於**只公開聚合結果**：個別行程留在個人手上，城市與企業看到的是需求曲線。

## 資料規則

- 不需要帳號。第一次登記時，瀏覽器取得 Supabase 匿名身分，登記只綁在這個身分上。
- 個別登記（`intents`）由 Row Level Security 保護：每人只能讀寫自己的那一筆，其他人（包含其他登入者）讀不到。
- 對外唯一的讀取管道是 `board_counts`、`board_total` 兩個函式：
  - 少於 3 人的時段只回傳「有人，但少於 3」，不給人數與方式。
  - 同一時段內少於 3 人的交通方式併入「其他」。
- 撤回即刪除該筆紀錄。

## 已知限制

- 匿名身分可以重複建立，目前沒有防止同一人多次登記（可在 Supabase 開啟 CAPTCHA 降低濫用）。
- 「少於 3 人不公開」可被差分攻擊部分推回（比較登記前後的合計）。正式版本需要延遲更新或加噪。
- 清除瀏覽器資料會失去匿名身分，舊登記會留在合計中，需要定期清理過期紀錄。

## 架構

- 前端：單一 `index.html`，部署在 GitHub Pages。
- 後端：Supabase（Postgres + RLS + Anonymous Auth + Realtime Broadcast）。
- `schema.sql`：資料表、權限規則與聚合函式，在 Supabase SQL Editor 執行一次即可。
- 前端裡的 `sb_publishable_...` 是公開金鑰，設計上就放在瀏覽器端；資料的保護靠 RLS，不靠金鑰保密。

## 新增地點

在 Supabase SQL Editor 執行：

```sql
insert into public.boards (id, name, place, day, start_time, end_time, sort)
values ('nangang-am', '南港軟體園區・平日晨間到達', '南港軟體園區', '平日', '07:00', '10:00', 2);
```
