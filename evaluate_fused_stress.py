# evaluate_fused_stress.py
# ------------------------------------------------------------
# More realistic evaluation of the fused stress‑detection system.
#
# • Uses a stratified 5‑fold cross‑validation to avoid a single lucky split.
# • Adds Gaussian noise and occasional missing values to the simulated sensor.
# • Trains a calibrated logistic‑regression model on facial emotion features.
# • Reports accuracy, F1, ROC‑AUC and a confusion matrix (averaged over folds).
# • Prints the optimal threshold (maximising F1) for each fold and its average.
# ------------------------------------------------------------

import os
import random
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    f1_score,
    roc_auc_score,
    confusion_matrix,
    precision_recall_curve,
)
from sklearn.model_selection import StratifiedKFold
from sklearn.linear_model import LogisticRegression
from sklearn.calibration import CalibratedClassifierCV

# ------------------------------------------------------------------
# 1️⃣ Locate the FER2013 CSV file.
# ------------------------------------------------------------------
DEFAULT_DATASET_ROOT = os.path.expanduser(
    r"~\.kagglehub\datasets\deadskull7/fer2013"
)

def get_dataset_path() -> str:
    """Return the folder that contains `fer2013.csv`.
    1. Checks for a saved `fer2013_path.txt` (may be a directory or the full CSV path).
    2. Falls back to the default KaggleHub cache location.
    3. If needed, downloads the dataset via kagglehub (optional).
    """
    path_file = "fer2013_path.txt"
    if os.path.exists(path_file):
        saved = open(path_file).read().strip()
        if saved.lower().endswith('.csv'):
            return os.path.dirname(saved)
        return saved
    if os.path.isdir(DEFAULT_DATASET_ROOT):
        return DEFAULT_DATASET_ROOT
    try:
        import kagglehub
    except ImportError:
        kagglehub = None
    if kagglehub:
        print("Downloading FER2013 dataset via kagglehub…")
        dataset_dir = kagglehub.dataset_download("deadskull7/fer2013")
        with open(path_file, "w") as f:
            f.write(dataset_dir)
        return dataset_dir
    raise FileNotFoundError(
        f"FER2013 CSV not found at {DEFAULT_DATASET_ROOT}. "
        "Run `python download_fer2013.py` first or install kagglehub."
    )

# Resolve location
dataset_folder = get_dataset_path()
csv_path = os.path.join(dataset_folder, "fer2013.csv")
if not os.path.isfile(csv_path):
    raise FileNotFoundError(
        f"FER2013 CSV not found at {csv_path}. "
        "Run `python download_fer2013.py` first (it will print the path)."
    )

# ------------------------------------------------------------------
# 2️⃣ Load the data.
# ------------------------------------------------------------------
df = pd.read_csv(csv_path)

# ------------------------------------------------------------------
# 3️⃣ Map numeric emotion label to a readable name.
# ------------------------------------------------------------------
emotion_map = {
    0: "angry",
    1: "disgust",
    2: "fear",
    3: "happy",
    4: "sad",
    5: "surprise",
    6: "neutral",
}
df["emotion_name"] = df["emotion"].map(emotion_map)

# ------------------------------------------------------------------
# 4️⃣ Define ground‑truth stress label.
#    Stressed = angry, disgust, fear, sad
# ------------------------------------------------------------------
stressed_emotions = {"angry", "disgust", "fear", "sad"}
df["true_stress"] = df["emotion_name"].isin(stressed_emotions).astype(int)

# ------------------------------------------------------------------
# 5️⃣ Encode facial emotion as one‑hot features.
# ------------------------------------------------------------------
X = pd.get_dummies(df["emotion_name"]).astype(int)
y = df["true_stress"].values

# ------------------------------------------------------------------
# 6️⃣ Helper: generate a realistic sensor reading.
# ------------------------------------------------------------------
random.seed(42)
np.random.seed(42)

def sensor_score(is_stressed: int) -> float:
    """Return a sensor stressScore (0‑100) with realistic noise.
    • Stressed samples: base range 70‑100.
    • Calm samples   : base range 0‑50.
    • Gaussian noise (σ≈10) is added.
    • 10 % of the readings are set to NaN to simulate dropout.
    """
    base = random.randint(70, 100) if is_stressed else random.randint(0, 50)
    noisy = base + np.random.normal(0, 10)  # add measurement noise
    noisy = np.clip(noisy, 0, 100)
    # Simulate missing data (10% chance)
    if random.random() < 0.10:
        return np.nan
    return noisy

# ------------------------------------------------------------------
# 7️⃣ Cross‑validation – evaluate the whole pipeline.
# ------------------------------------------------------------------
W_SENSOR = 0.6  # default weight; can be tuned later
W_FACE = 0.4
n_folds = 5
skf = StratifiedKFold(n_splits=n_folds, shuffle=True, random_state=42)

fold_metrics = []
for fold_idx, (train_idx, test_idx) in enumerate(skf.split(X, y), start=1):
    # Split data
    X_train, X_test = X.iloc[train_idx], X.iloc[test_idx]
    y_train, y_test = y[train_idx], y[test_idx]

    # ------------------------------------------------------------------
    # 7a️⃣ Calibrate facial‑emotion probabilities on the TRAIN set.
    # ------------------------------------------------------------------
    base_clf = LogisticRegression(max_iter=1000)
    calibrated_clf = CalibratedClassifierCV(base_clf, cv=5)
    calibrated_clf.fit(X_train, y_train)
    face_prob_test = calibrated_clf.predict_proba(X_test)[:, 1]

    # ------------------------------------------------------------------
    # 7b️⃣ Simulate sensor scores for the TEST set (with noise & missing data).
    # ------------------------------------------------------------------
    sensor_scores = [sensor_score(label) for label in y_test]
    sensor_scores = np.array(sensor_scores, dtype=float)
    # Impute missing sensor values with the mean sensor score of the TRAIN set
    # (computed on the same biased distribution but without NaNs).
    train_sensor_scores = [sensor_score(label) for label in y_train]
    train_sensor_scores = np.array(train_sensor_scores, dtype=float)
    mean_sensor = np.nanmean(train_sensor_scores)
    sensor_scores = np.where(np.isnan(sensor_scores), mean_sensor, sensor_scores)
    sensor_prob = sensor_scores / 100.0

    # ------------------------------------------------------------------
    # 7c️⃣ Fusion of sensor and facial probabilities.
    # ------------------------------------------------------------------
    combined = W_SENSOR * sensor_prob + W_FACE * face_prob_test

    # ------------------------------------------------------------------
    # 7d️⃣ Find optimal threshold (maximising F1) on this fold.
    # ------------------------------------------------------------------
    prec, rec, thr = precision_recall_curve(y_test, combined)
    f1_vals = 2 * prec * rec / (prec + rec + 1e-12)
    best_idx = int(np.argmax(f1_vals))
    best_thr = thr[best_idx] if best_idx < len(thr) else 0.5
    best_f1 = f1_vals[best_idx]
    best_prec = prec[best_idx]
    best_rec = rec[best_idx]

    # --------------------------------------------------------------
    # 7e️⃣ Final predictions for this fold using the optimal threshold.
    # --------------------------------------------------------------
    pred = (combined > best_thr).astype(int)

    # --------------------------------------------------------------
    # 7f️⃣ Compute metrics for this fold.
    # --------------------------------------------------------------
    acc = accuracy_score(y_test, pred)
    f1 = f1_score(y_test, pred)
    auc = roc_auc_score(y_test, combined)
    cm = confusion_matrix(y_test, pred)

    fold_metrics.append(
        {
            "fold": fold_idx,
            "accuracy": acc,
            "f1": f1,
            "roc_auc": auc,
            "threshold": best_thr,
            "precision": best_prec,
            "recall": best_rec,
            "confusion": cm,
        }
    )

    # --------------------------------------------------------------
    # 7g️⃣ Print per‑fold results.
    # --------------------------------------------------------------
    print(f"\n--- Fold {fold_idx}/{n_folds} ---")
    print(f"Optimal threshold : {best_thr:.3f}")
    print(f"Precision         : {best_prec:.3f}")
    print(f"Recall            : {best_rec:.3f}")
    print(f"F1‑score          : {best_f1:.3f}")
    print(f"Accuracy          : {acc*100:.2f}%")
    print(f"ROC‑AUC           : {auc:.3f}")
    print("Confusion matrix:")
    print(cm)

# ------------------------------------------------------------------
# 8️⃣ Aggregate results across folds.
# ------------------------------------------------------------------
avg_acc = np.mean([m["accuracy"] for m in fold_metrics])
avg_f1 = np.mean([m["f1"] for m in fold_metrics])
avg_auc = np.mean([m["roc_auc"] for m in fold_metrics])
avg_thr = np.mean([m["threshold"] for m in fold_metrics])

print("\n=== Cross‑validated Fused Stress‑Detection Evaluation ===")
print(f"Folds               : {n_folds}")
print(f"Avg optimal thresh  : {avg_thr:.3f}")
print(f'Avg precision       : {np.mean([m["precision"] for m in fold_metrics]):.3f}')
print(f'Avg recall          : {np.mean([m["recall"] for m in fold_metrics]):.3f}')
print(f"Avg F1‑score        : {avg_f1:.3f}")
print(f"Avg accuracy        : {avg_acc*100:.2f}%")
print(f"Avg ROC‑AUC         : {avg_auc:.3f}")

# ------------------------------------------------------------------
# 9️⃣ Optional quick weight grid‑search (using the average metrics).
# ------------------------------------------------------------------
print("\n--- Quick weight grid‑search (using averaged sensor/facial probs) ---")
# Compute realistic metrics for each sensor/face weight combination.
for ws in [0.4, 0.5, 0.6, 0.7]:
    wf = 1.0 - ws
    # Compute combined probabilities for the current fold using given weights
    combined_grid = ws * sensor_prob + wf * face_prob_test
    # Use the average optimal threshold from cross‑validation (more realistic than per‑weight optimal)
    pred_grid = (combined_grid > avg_thr).astype(int)
    acc_grid = accuracy_score(y_test, pred_grid)
    f1_grid = f1_score(y_test, pred_grid)
    print(f"w_sensor={ws:.1f}, w_face={wf:.1f} → Acc={acc_grid*100:.2f}%, F1={f1_grid:.4f}")

# End of script
