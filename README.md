# FF14 金碟 G.A.T.E. 自動循環（SND）

`GATE_AutoLoop.lua`：每 20 分鐘（地球時間 :00 / :20 / :40）自動找「活動解說員」詢問目前的 G.A.T.E.，傳送到現場並報名。進場後由 [Saucy](https://github.com/PunishXIV/Saucy) 自動玩。限繁中客戶端。

## 需要
- SomethingNeedDoing
- vnavmesh
- Saucy（插件庫 `https://love.puni.sh/ment.json`）：開啟「必中一閃快刀斬魔」「暴風倖存者」「空軍裝甲駕駛員」三個模組，前兩個要勾「自動移動」
- BossMod：快刀斬魔的閃避要用到
- TextAdvance（建議）：自動點掉對話框

## 支援的 G.A.T.E.
| G.A.T.E. | 設定 | 預設 |
|---|---|---|
| 必中一閃快刀斬魔 | `JoinSlice` | 開 |
| 暴風倖存者 | `JoinWind` | 開 |
| 空軍裝甲駕駛員 | `JoinAirForce` | 開 |
| 登高跳跳樂大挑戰 | `JoinLeap` | 關（Saucy 不支援） |
| 搶救小雛鳥大作戰 | `JoinCliff` | 關（Saucy 不支援） |

`MaxGates` 是參加幾場後停止，0 = 無限循環。

## 狀態
還沒在遊戲裡實測過。每一步都會用 `[GATE]` 開頭印在聊天欄，有問題就看這些訊息。
